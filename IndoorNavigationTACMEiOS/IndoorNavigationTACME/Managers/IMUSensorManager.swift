//
//  IMUSensorManager.swift
//  IndoorNavigationTACME
//
//

import Foundation
import CoreMotion
import Combine

class IMUSensorManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var imuState = IMUState()
    
    // MARK: - Private Properties
    private let motionManager = CMMotionManager()
    private var calibrationManager: IMUCalibrationManager?
    private let stepFactorCalibration = UserStepFactorCalibration()
    
    // Sensor update interval
    private let sensorUpdateInterval: TimeInterval = 0.02 // 50Hz
    
    // Dedicated serial queue for all sensor processing (keeps main thread free)
    private let sensorQueue = DispatchQueue(label: "com.tacme.imu.sensor", qos: .userInteractive)
    
    // Position tracking
    private var currentX: Double = 0
    private var currentY: Double = 0
    private var currentBearing: Double = 0
    private var stepCount: Int = 0
    private var currentStepLength: Double = 0.65
    
    // Gyroscope integration
    private var gyroIntegrationBearing: Double = 0
    private var initialBearingSet: Bool = false
    private var lastTimestamp: TimeInterval = 0
    
    // Step detection - MATCHING ANDROID
    private var filteredAcceleration: [Double] = []
    private var accelerationTimestamps: [TimeInterval] = []
    private var accelerationVariances: [Double] = []
    private var detectedPeaks: [Double] = []
    private var recentStepPeriods: [TimeInterval] = []
    private var lastStepTime: Date?
    private var pendingStepCandidateTime: Date?
    
    // Peak-valley detection (ADAPTED FOR iOS — userAcceleration has gravity removed,
    // so magnitudes are ~0–1g vs Android's ~7–12g raw. Threshold is lower accordingly.)
    private var lastPeak: Double = 0
    private var lastValley: Double = 0
    private var lastPeakTime: TimeInterval = 0
    private let stepPeakThreshold: Double = 0.08
    
    // Real Butterworth bandpass filter (SAME COEFFICIENTS AS ANDROID)
    private let butterworthFilter = ButterworthBandpassFilter()
    
    // Filter parameters
    private let dynamicWindowSize = 50
    private let varianceThreshold: Double = 0.005
    
    // Bearing correction
    private var pathBearings: [Double] = []
    private var currentSegmentId: Int = -1
    private var bearingCorrectionCount: Int = 0
    private let bearingCorrectionThreshold: Double = 25.0
    
    // Constants
    private let gyroNoiseThreshold: Double = 0.01
    private let maxGyroRate: Double = 5.0
    private let defaultBeta: Double = 0.6
    
    // Step timing constraints
    private let minStepPeriod: TimeInterval = 0.3
    private let maxStepPeriod: TimeInterval = 1.2
    private let stationaryVarianceGateMultiplier: Double = 0.8
    
    // Acceleration logging
    private var accelerationLogger = AccelerationLogger()
    
    // Debug
    private var totalSamples: Int = 0
    private var lastDebugLog: Date = Date.distantPast
    
    // MARK: - Initialization
    init() {
        setupMotionManager()
        imuState.beta = stepFactorCalibration.getUserBeta()
        imuState.isStepCalibrationValid = stepFactorCalibration.isCalibrationValid()
        print("IMUSensorManager: Initialized")
    }
    
    deinit {
        stopSensors()
    }
    
    // MARK: - Public Methods
    
    func setCalibrationManager(_ manager: IMUCalibrationManager) {
        self.calibrationManager = manager
    }
    
    func startSensors() {
        guard motionManager.isDeviceMotionAvailable else {
            print("IMUSensorManager: Device motion not available")
            return
        }
        
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: OperationQueue()) { [weak self] motion, error in
            guard let self = self, let motion = motion else {
                if let error = error {
                    print("IMUSensorManager: Motion error: \(error)")
                }
                return
            }
            // Process sensor data on dedicated background queue (not main thread)
            self.sensorQueue.async {
                self.processMotionUpdate(motion)
            }
        }
        
        print("IMUSensorManager: Started updates at \(1.0/sensorUpdateInterval)Hz")
    }
    
    func stopSensors() {
        motionManager.stopDeviceMotionUpdates()
        print("IMUSensorManager: Sensors stopped")
    }
    
    func resetPosition() {
        currentX = 0
        currentY = 0
        stepCount = 0
        filteredAcceleration.removeAll()
        accelerationTimestamps.removeAll()
        accelerationVariances.removeAll()
        detectedPeaks.removeAll()
        recentStepPeriods.removeAll()
        lastStepTime = nil
        pendingStepCandidateTime = nil
        lastPeak = 0
        lastValley = 0
        lastPeakTime = 0
        butterworthFilter.reset()
        accelerationLogger.clear()
        totalSamples = 0
        updateIMUState()
        print("IMUSensorManager: Position reset")
    }
    
    func setInitialBearing(_ bearing: Double) {
        gyroIntegrationBearing = bearing
        currentBearing = bearing
        initialBearingSet = true
        print("IMUSensorManager: Initial bearing set to \(bearing)°")
    }
    
    func getCurrentPosition() -> Position {
        return Position(x: currentX, y: currentY, bearing: currentBearing)
    }
    
    func getCurrentMapPosition() -> Position? {
        return calibrationManager?.transformToMapPosition(getCurrentPosition())
    }
    
    func setBearingCorrectionData(_ bearings: [Double], _ segmentId: Int) {
        pathBearings = bearings
        currentSegmentId = segmentId
        print("IMUSensorManager: Bearing correction data set - \(bearings.count) bearings, segment \(segmentId)")
    }
    
    func startStepCalibration() {
        stepFactorCalibration.startCalibration()
        imuState.isCalibrating = true
    }
    
    func completeStepCalibration() {
        stepFactorCalibration.completeCalibration()
        imuState.beta = stepFactorCalibration.getUserBeta()
        imuState.isStepCalibrationValid = stepFactorCalibration.isCalibrationValid()
        imuState.isCalibrating = false
    }
    
    func stopStepCalibration() {
        let _ = stepFactorCalibration.stopCalibration()
        imuState.beta = stepFactorCalibration.getUserBeta()
        imuState.isStepCalibrationValid = stepFactorCalibration.isCalibrationValid()
        imuState.isCalibrating = false
    }
    
    func getStepDetectionMetrics() -> [String: Any] {
        return [
            "totalSteps": stepCount,
            "averageStepLength": String(format: "%.2f", currentStepLength),
            "recentStepPeriods": recentStepPeriods.suffix(5),
            "dynamicWindowSize": dynamicWindowSize,
            "filterStatus": "Butterworth 0.8-4Hz",
            "totalSamples": totalSamples,
            "lastPeak": String(format: "%.4f", lastPeak),
            "lastValley": String(format: "%.4f", lastValley)
        ]
    }
    
    func getBearingCorrectionStats() -> [String: Any] {
        return [
            "pathBearingsCount": pathBearings.count,
            "currentSegmentId": currentSegmentId,
            "bearingCorrectionCount": bearingCorrectionCount,
            "bearingThreshold": bearingCorrectionThreshold,
            "currentBearing": String(format: "%.1f°", currentBearing)
        ]
    }
    
    func getAccelerationSamples() -> [AccelerationSample] {
        return accelerationLogger.getSamples()
    }
    
    func getAccelerationLoggerStatistics() -> (totalSamples: Int, peakCount: Int, valleyCount: Int, confirmedStepCount: Int, timeSpanMs: Int64) {
        return accelerationLogger.getStatistics()
    }
    
    func getSensorStatus() -> [String: Any] {
        return [
            "isInitialized": motionManager.isDeviceMotionActive,
            "stepCount": stepCount,
            "position": "(\(String(format: "%.2f", currentX)), \(String(format: "%.2f", currentY)))",
            "bearing": "\(String(format: "%.1f", currentBearing))°",
            "currentStepLength": "\(String(format: "%.2f", currentStepLength))m",
            "dynamicWindowSize": dynamicWindowSize,
            "filterQuality": imuState.filterQuality,
            "detectedPeaks": detectedPeaks.count,
            "totalSamples": totalSamples
        ]
    }
    
    // MARK: - Private Methods
    
    private func setupMotionManager() {
        motionManager.deviceMotionUpdateInterval = sensorUpdateInterval
    }
    
    private func processMotionUpdate(_ motion: CMDeviceMotion) {
        let timestamp = motion.timestamp
        processAccelerometer(motion.userAcceleration, timestamp: timestamp)
        processGyroscope(motion.rotationRate, timestamp: timestamp)
        updateIMUState()
    }
    
    private func processAccelerometer(_ acceleration: CMAcceleration, timestamp: TimeInterval) {
        // iOS userAcceleration already has gravity removed (values ~0 to ~3)
        let magnitude = sqrt(acceleration.x * acceleration.x +
                            acceleration.y * acceleration.y +
                            acceleration.z * acceleration.z)
        
        totalSamples += 1
        
        // Apply REAL Butterworth bandpass filter (0.8-4Hz)
        let filtered = butterworthFilter.filter(magnitude)
        
        // Log sample
        accelerationLogger.addSample(AccelerationSample(
            sampleIndex: 0, // overridden by logger
            timestamp: Date(),
            x: acceleration.x,
            y: acceleration.y,
            z: acceleration.z,
            magnitude: magnitude,
            filtered: filtered
        ))
        
        accelerationTimestamps.append(timestamp)
        filteredAcceleration.append(filtered)
        
        // Maintain window
        if filteredAcceleration.count > dynamicWindowSize {
            filteredAcceleration.removeFirst()
            accelerationTimestamps.removeFirst()
        }
        
        // Calculate variance
        if filteredAcceleration.count >= dynamicWindowSize {
            let variance = calculateVariance(Array(filteredAcceleration))
            accelerationVariances.append(variance)
            if accelerationVariances.count > dynamicWindowSize {
                accelerationVariances.removeFirst()
            }
        }
        
        // Peak-valley step detection
        if filteredAcceleration.count >= 3 {
            detectPeaksAndValidateSteps(timestamp: timestamp)
        }
        
        // Periodic debug logging (every 5 seconds)
        if Date().timeIntervalSince(lastDebugLog) > 5.0 && totalSamples > 0 {
            lastDebugLog = Date()
            let recentMax = filteredAcceleration.max() ?? 0
            let recentMin = filteredAcceleration.min() ?? 0
            print("IMUSensorManager: [DEBUG] samples=\(totalSamples), steps=\(stepCount), range=[\(String(format: "%.4f", recentMin))...\(String(format: "%.4f", recentMax))], peak=\(String(format: "%.4f", lastPeak)), valley=\(String(format: "%.4f", lastValley))")
        }
    }
    
    // MARK: - Peak-Valley Step Detection
    
    private func detectPeaksAndValidateSteps(timestamp: TimeInterval) {
        guard filteredAcceleration.count >= 3 else { return }
        
        let mean = filteredAcceleration.reduce(0, +) / Double(filteredAcceleration.count)
        let std = calculateStd(filteredAcceleration, mean: mean)
        
        let upperThreshold = mean + std * 1.0
        let lowerThreshold = mean - std * 0.5
        
        let n = filteredAcceleration.count
        let current = filteredAcceleration[n - 1]
        let previous = filteredAcceleration[n - 2]
        let beforePrevious = filteredAcceleration[n - 3]
        
        // Peak detection: previous is a local maximum above the dynamic upper threshold
        if previous > beforePrevious &&
           previous > current &&
           previous > upperThreshold {
            lastPeak = previous
            lastPeakTime = accelerationTimestamps.count >= 2 ?
                accelerationTimestamps[accelerationTimestamps.count - 2] : timestamp
            accelerationLogger.markLastSampleAsPeak()
        }
        
        // Valley detection: previous is a local minimum below lower threshold (after a peak)
        if previous < beforePrevious &&
           previous < current &&
           previous < lowerThreshold &&
           lastPeakTime > 0 {
            
            lastValley = previous
            let peakValleyDiff = lastPeak - lastValley
            accelerationLogger.markLastSampleAsValley()
            
            if peakValleyDiff > stepPeakThreshold {
                let currentDate = Date()
                let recentVariance = accelerationVariances.suffix(5).reduce(0, +) /
                    Double(max(accelerationVariances.suffix(5).count, 1))
                let isStationary = recentVariance < (varianceThreshold * stationaryVarianceGateMultiplier)

                // Reject weak peaks when recent motion variance indicates stationary behavior.
                if isStationary && peakValleyDiff < (stepPeakThreshold * 1.8) {
                    pendingStepCandidateTime = nil
                    return
                }
                
                if let lastStep = lastStepTime {
                    let timeSinceLastStep = currentDate.timeIntervalSince(lastStep)
                    
                    if timeSinceLastStep >= minStepPeriod && timeSinceLastStep <= maxStepPeriod {
                        confirmStep(peakValleyDiff: peakValleyDiff, period: timeSinceLastStep, date: currentDate)
                    } else if timeSinceLastStep > maxStepPeriod {
                        // Require two close candidates to resume counting after long idle periods.
                        if let candidateTime = pendingStepCandidateTime {
                            let candidateGap = currentDate.timeIntervalSince(candidateTime)
                            if candidateGap >= minStepPeriod && candidateGap <= maxStepPeriod {
                                confirmStep(peakValleyDiff: peakValleyDiff, period: candidateGap, date: currentDate)
                                pendingStepCandidateTime = nil
                            } else {
                                pendingStepCandidateTime = currentDate
                            }
                        } else {
                            pendingStepCandidateTime = currentDate
                        }
                    }
                } else {
                    if let candidateTime = pendingStepCandidateTime {
                        let candidateGap = currentDate.timeIntervalSince(candidateTime)
                        if candidateGap >= minStepPeriod && candidateGap <= maxStepPeriod {
                            confirmStep(peakValleyDiff: peakValleyDiff, period: candidateGap, date: currentDate)
                            pendingStepCandidateTime = nil
                        } else {
                            pendingStepCandidateTime = currentDate
                        }
                    } else {
                        pendingStepCandidateTime = currentDate
                    }
                }
            }
        }
    }
    
    private func confirmStep(peakValleyDiff: Double, period: TimeInterval, date: Date) {
        stepCount += 1
        lastStepTime = date
        pendingStepCandidateTime = nil
        
        recentStepPeriods.append(period)
        if recentStepPeriods.count > 10 { recentStepPeriods.removeFirst() }
        
        let beta = stepFactorCalibration.isCalibrationValid() ?
            stepFactorCalibration.getUserBeta() : defaultBeta
        currentStepLength = beta * pow(peakValleyDiff, 0.25)
        currentStepLength = min(max(currentStepLength, 0.3), 1.2)
        
        // Mark sample as confirmed step (Android parity)
        accelerationLogger.markSampleAsConfirmedStep(
            timestamp: date,
            stepLength: currentStepLength,
            stepNumber: stepCount,
            peakValleyDiff: peakValleyDiff
        )
        
        if stepFactorCalibration.isCalibrating {
            stepFactorCalibration.addStepData(peakValleyDifference: peakValleyDiff)
        }
        
        detectedPeaks.append(lastPeak)
        if detectedPeaks.count > 20 { detectedPeaks.removeFirst() }
        
        updatePosition()
        calibrationManager?.updateCalibration(currentImuPosition: getCurrentPosition(), stepCount: stepCount)
        
        print("IMUSensorManager: Step #\(stepCount) pvDiff=\(String(format: "%.3f", peakValleyDiff)), len=\(String(format: "%.2f", currentStepLength))m, bearing=\(String(format: "%.1f", currentBearing))°")
    }
    
    private func processGyroscope(_ rotationRate: CMRotationRate, timestamp: TimeInterval) {
        guard initialBearingSet else { return }
        
        if lastTimestamp != 0 {
            let dt = timestamp - lastTimestamp
            let gyroZ = rotationRate.z
            
            if abs(gyroZ) >= gyroNoiseThreshold && abs(gyroZ) <= maxGyroRate {
                let deltaBearing = gyroZ * dt * (-180.0 / .pi)
                gyroIntegrationBearing = (gyroIntegrationBearing + deltaBearing)
                    .truncatingRemainder(dividingBy: 360)
                if gyroIntegrationBearing < 0 { gyroIntegrationBearing += 360 }
                
                let result = applyBearingCorrection(gyroIntegrationBearing)
                currentBearing = result.bearing
            }
        }
        
        lastTimestamp = timestamp
    }
    
    private func updatePosition() {
        let bearingRad = currentBearing * .pi / 180.0
        currentX += currentStepLength * sin(bearingRad)
        currentY += currentStepLength * cos(bearingRad)
    }
    
    private func applyBearingCorrection(_ rawBearing: Double) -> BearingResult {
        guard currentSegmentId >= 0 && currentSegmentId < pathBearings.count else {
            return BearingResult(rawBearing, false)
        }
        let trueBearing = pathBearings[currentSegmentId]
        let diff = calculateBearingDifference(rawBearing, trueBearing)
        if abs(diff) <= bearingCorrectionThreshold {
            bearingCorrectionCount += 1
            return BearingResult(trueBearing, true)
        }
        return BearingResult(rawBearing, false)
    }
    
    private func calculateBearingDifference(_ bearing1: Double, _ bearing2: Double) -> Double {
        var diff = bearing1 - bearing2
        while diff > 180 { diff -= 360 }
        while diff < -180 { diff += 360 }
        return diff
    }
    
    private func calculateVariance(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
    }
    
    private func calculateStd(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }
    
    private func updateIMUState() {
        let isMoving = !accelerationVariances.isEmpty &&
                       accelerationVariances.suffix(3).contains { $0 > varianceThreshold }
        
        let filterQuality: String
        if detectedPeaks.count >= 3 && !recentStepPeriods.isEmpty {
            filterQuality = "Excellent"
        } else if filteredAcceleration.count >= dynamicWindowSize {
            filterQuality = "Good"
        } else {
            filterQuality = "Initializing"
        }
        
        let calibrationStepCount = stepFactorCalibration.getCalibrationStepCount()
        
        let newState = IMUState(
            position: getCurrentPosition(),
            stepCount: stepCount,
            isCalibrated: calibrationManager?.isCalibrationValid() ?? false,
            accelerationMagnitude: Float(filteredAcceleration.last ?? 0),
            isMoving: isMoving,
            currentStepLength: currentStepLength,
            filterQuality: filterQuality,
            beta: stepFactorCalibration.getUserBeta(),
            isStepCalibrationValid: stepFactorCalibration.isCalibrationValid(),
            isCalibrating: stepFactorCalibration.isCalibrating,
            calibrationStepCount: calibrationStepCount,
            bearing: currentBearing
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.imuState = newState
        }
    }
}

// MARK: - Real Butterworth Bandpass Filter (SAME AS ANDROID)

class ButterworthBandpassFilter {
    private let a0: Double = 1.0
    private let a1: Double = -1.6255829582907484
    private let a2: Double = 0.6675381679326730
    private let b0: Double = 0.16623091603366352
    private let b1: Double = 0.0
    private let b2: Double = -0.16623091603366352
    
    private var x1: Double = 0
    private var x2: Double = 0
    private var y1: Double = 0
    private var y2: Double = 0
    
    func filter(_ input: Double) -> Double {
        let output = (b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2 = x1; x1 = input
        y2 = y1; y1 = output
        return output
    }
    
    func reset() {
        x1 = 0; x2 = 0
        y1 = 0; y2 = 0
    }
}

// MARK: - User Step Factor Calibration

class UserStepFactorCalibration {
    
    private(set) var isCalibrating: Bool = false
    private var userStepCount: Int = 0
    private var accumulatedAccelerationDiff: Double = 0
    private var userBeta: Double = 0.6
    private var calibratedBeta: Double = 0.6
    private var isValid: Bool = false
    
    private let calibrationDistance: Double = 20.0
    private let defaultBeta: Double = 0.6
    private let calibrationBetaKey = "imu.stepCalibration.beta"
    private let calibrationValidKey = "imu.stepCalibration.isValid"

    init() {
        loadPersistedCalibration()
    }
    
    func startCalibration() {
        isCalibrating = true
        userStepCount = 0
        accumulatedAccelerationDiff = 0
    }
    
    func addStepData(peakValleyDifference: Double) {
        guard isCalibrating && peakValleyDifference > 0 else { return }
        let accDiff = pow(peakValleyDifference, 0.25)
        accumulatedAccelerationDiff += accDiff
        userStepCount += 1
    }
    
    func completeCalibration() {
        guard isCalibrating else { return }
        if accumulatedAccelerationDiff > 0 {
            userBeta = calibrationDistance / accumulatedAccelerationDiff
            isValid = userBeta > 0.1 && userBeta < 2.0
            if isValid {
                calibratedBeta = userBeta
                persistCalibration()
            }
        }
        isCalibrating = false
    }
    
    func stopCalibration() -> Bool {
        guard isCalibrating else { return false }
        if accumulatedAccelerationDiff > 0 && userStepCount > 0 {
            let estimatedDistance = Double(userStepCount) * 0.65
            userBeta = estimatedDistance / accumulatedAccelerationDiff
            isValid = userBeta > 0.1 && userBeta < 2.0
            if isValid {
                calibratedBeta = userBeta
                persistCalibration()
            }
        }
        isCalibrating = false
        return isValid
    }
    
    func cancel() {
        isCalibrating = false
        userStepCount = 0
        accumulatedAccelerationDiff = 0
    }
    
    func getCalibrationStepCount() -> Int {
        return userStepCount
    }
    
    func getUserBeta() -> Double {
        return isValid ? calibratedBeta : defaultBeta
    }
    
    func isCalibrationValid() -> Bool {
        return isValid
    }

    private func persistCalibration() {
        UserDefaults.standard.set(calibratedBeta, forKey: calibrationBetaKey)
        UserDefaults.standard.set(isValid, forKey: calibrationValidKey)
    }

    private func loadPersistedCalibration() {
        let wasValid = UserDefaults.standard.bool(forKey: calibrationValidKey)
        guard wasValid else { return }

        let storedBeta = UserDefaults.standard.double(forKey: calibrationBetaKey)
        guard storedBeta > 0.1 && storedBeta < 2.0 else { return }

        calibratedBeta = storedBeta
        userBeta = storedBeta
        isValid = true
    }
}

// MARK: - Acceleration Logger

/// Logger matching Android's AccelerationDataLogger.
/// Stores samples and allows retroactive marking of peaks, valleys, and confirmed steps.
class AccelerationLogger {
    private var samples: [AccelerationSample] = []
    private let maxSamples = 10000
    private var sampleCounter: Int = 0
    
    func addSample(_ sample: AccelerationSample) {
        var s = sample
        s = AccelerationSample(
            sampleIndex: sampleCounter,
            timestamp: s.timestamp,
            x: s.x, y: s.y, z: s.z,
            magnitude: s.magnitude,
            filtered: s.filtered,
            isPeak: s.isPeak,
            isValley: s.isValley,
            isConfirmedStep: s.isConfirmedStep,
            stepLength: s.stepLength,
            stepNumber: s.stepNumber,
            peakValleyDiff: s.peakValleyDiff
        )
        samples.append(s)
        sampleCounter += 1
        if samples.count > maxSamples { samples.removeFirst() }
    }
    
    /// Mark the second-to-last sample as a detected peak (matching Android)
    func markLastSampleAsPeak() {
        guard samples.count >= 2 else { return }
        let idx = samples.count - 2
        samples[idx].isPeak = true
    }
    
    /// Mark the second-to-last sample as a detected valley (matching Android)
    func markLastSampleAsValley() {
        guard samples.count >= 2 else { return }
        let idx = samples.count - 2
        samples[idx].isValley = true
    }
    
    /// Mark a sample (by closest timestamp) as a confirmed step
    func markSampleAsConfirmedStep(timestamp: Date, stepLength: Double, stepNumber: Int, peakValleyDiff: Double) {
        // Find the sample closest to the given timestamp
        guard let idx = samples.lastIndex(where: { abs($0.timestamp.timeIntervalSince(timestamp)) < 0.5 }) else { return }
        samples[idx].isConfirmedStep = true
        samples[idx].stepLength = stepLength
        samples[idx].stepNumber = stepNumber
        samples[idx].peakValleyDiff = peakValleyDiff
    }
    
    func getSamples() -> [AccelerationSample] { return samples }
    
    func getStatistics() -> (totalSamples: Int, peakCount: Int, valleyCount: Int, confirmedStepCount: Int, timeSpanMs: Int64) {
        let peaks = samples.filter { $0.isPeak }.count
        let valleys = samples.filter { $0.isValley }.count
        let steps = samples.filter { $0.isConfirmedStep }.count
        let span: Int64 = samples.count >= 2
            ? Int64(samples.last!.timestamp.timeIntervalSince(samples.first!.timestamp) * 1000)
            : 0
        return (samples.count, peaks, valleys, steps, span)
    }
    
    func clear() {
        samples.removeAll()
        sampleCounter = 0
    }
}
