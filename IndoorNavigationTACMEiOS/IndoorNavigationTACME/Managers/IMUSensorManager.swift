//
//  IMUSensorManager.swift
//  IndoorNavigationTACME
//
//  Manages IMU sensors (accelerometer, gyroscope) for indoor navigation
//

import Foundation
import CoreMotion
import Combine

/// Manages IMU sensors for step detection and position tracking
class IMUSensorManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var imuState = IMUState()
    
    // MARK: - Private Properties
    
    private let motionManager = CMMotionManager()
    private var calibrationManager: IMUCalibrationManager?
    private let stepFactorCalibration = UserStepFactorCalibration()
    
    // Sensor update interval
    private let sensorUpdateInterval: TimeInterval = 0.02 // 50Hz
    
    // Position tracking
    private var currentX: Double = 0
    private var currentY: Double = 0
    private var currentBearing: Double = 0
    private var stepCount: Int = 0
    private var currentStepLength: Double = 0.65 // Default step length
    
    // Gyroscope integration
    private var gyroIntegrationBearing: Double = 0
    private var initialBearingSet: Bool = false
    private var lastTimestamp: TimeInterval = 0
    
    // Step detection
    private var filteredAcceleration: [Double] = []
    private var accelerationVariances: [Double] = []
    private var detectedPeaks: [Double] = []
    private var recentStepPeriods: [TimeInterval] = []
    private var lastStepTime: Date?
    
    // Filter parameters
    private let dynamicWindowSize = 20
    private let varianceThreshold: Double = 0.02
    
    // Butterworth filter coefficients (0.8-4Hz bandpass at 50Hz sample rate)
    private var filterBuffer: [Double] = []
    private let filterOrder = 2
    
    // Bearing correction
    private var pathBearings: [Double] = []
    private var currentSegmentId: Int = -1
    private var bearingCorrectionCount: Int = 0
    private let bearingCorrectionThreshold: Double = 25.0
    
    // Constants
    private let gyroNoiseThreshold: Double = 0.01
    private let maxGyroRate: Double = 5.0
    private let defaultBeta: Double = 0.6
    
    // Acceleration logging
    private var accelerationLogger = AccelerationLogger()
    
    // MARK: - Initialization
    
    init() {
        setupMotionManager()
    }
    
    deinit {
        stopSensors()
    }
    
    // MARK: - Public Methods
    
    /// Set the calibration manager reference
    func setCalibrationManager(_ manager: IMUCalibrationManager) {
        self.calibrationManager = manager
    }
    
    /// Start sensor updates
    func startSensors() {
        guard motionManager.isDeviceMotionAvailable else {
            print("IMUSensorManager: Device motion not available")
            return
        }
        
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else {
                if let error = error {
                    print("IMUSensorManager: Motion update error: \(error)")
                }
                return
            }
            self.processMotionUpdate(motion)
        }
        
        print("IMUSensorManager: Sensors started")
    }
    
    /// Stop sensor updates
    func stopSensors() {
        motionManager.stopDeviceMotionUpdates()
        print("IMUSensorManager: Sensors stopped")
    }
    
    /// Reset position to origin
    func resetPosition() {
        currentX = 0
        currentY = 0
        stepCount = 0
        filteredAcceleration.removeAll()
        accelerationVariances.removeAll()
        detectedPeaks.removeAll()
        recentStepPeriods.removeAll()
        lastStepTime = nil
        filterBuffer.removeAll()
        accelerationLogger.clear()
        updateIMUState()
        print("IMUSensorManager: Position reset")
    }
    
    /// Set initial bearing from calibration
    func setInitialBearing(_ bearing: Double) {
        gyroIntegrationBearing = bearing
        currentBearing = bearing
        initialBearingSet = true
        print("IMUSensorManager: Initial bearing set to \(bearing)°")
    }
    
    /// Get current position
    func getCurrentPosition() -> Position {
        return Position(x: currentX, y: currentY, bearing: currentBearing, timestamp: Date())
    }
    
    /// Get current position transformed to map coordinates
    func getCurrentMapPosition() -> Position? {
        return calibrationManager?.transformToMapPosition(getCurrentPosition())
    }
    
    /// Set bearing correction data from server
    func setBearingCorrectionData(_ bearings: [Double], _ segmentId: Int) {
        pathBearings = bearings
        currentSegmentId = segmentId
        print("IMUSensorManager: Bearing correction data set - \(bearings.count) bearings, segment \(segmentId)")
    }
    
    // MARK: - Step Calibration
    
    /// Start step length calibration
    func startStepCalibration() {
        stepFactorCalibration.startCalibration()
        imuState.isStepCalibrating = true
        print("IMUSensorManager: Step calibration started")
    }
    
    /// Complete step calibration
    func completeStepCalibration() {
        stepFactorCalibration.completeCalibration()
        imuState.userBeta = stepFactorCalibration.getUserBeta()
        imuState.isStepCalibrationValid = stepFactorCalibration.isCalibrationValid()
        imuState.isStepCalibrating = false
        print("IMUSensorManager: Step calibration completed - beta: \(imuState.userBeta)")
    }
    
    /// Stop step calibration
    func stopStepCalibration() {
        let _ = stepFactorCalibration.stopCalibration()
        imuState.userBeta = stepFactorCalibration.getUserBeta()
        imuState.isStepCalibrationValid = stepFactorCalibration.isCalibrationValid()
        imuState.isStepCalibrating = false
        print("IMUSensorManager: Step calibration stopped")
    }
    
    // MARK: - Debug Methods
    
    /// Get step detection metrics
    func getStepDetectionMetrics() -> [String: Any] {
        return [
            "totalSteps": stepCount,
            "averageStepLength": String(format: "%.2f", currentStepLength),
            "recentStepPeriods": recentStepPeriods.suffix(5),
            "dynamicWindowSize": dynamicWindowSize,
            "filterStatus": "Butterworth 0.8-4Hz"
        ]
    }
    
    /// Get bearing correction stats
    func getBearingCorrectionStats() -> [String: Any] {
        return [
            "pathBearingsCount": pathBearings.count,
            "currentSegmentId": currentSegmentId,
            "bearingCorrectionCount": bearingCorrectionCount,
            "bearingThreshold": bearingCorrectionThreshold,
            "currentBearing": String(format: "%.1f°", currentBearing)
        ]
    }
    
    /// Get acceleration samples for debugging
    func getAccelerationSamples() -> [AccelerationSample] {
        return accelerationLogger.getSamples()
    }
    
    // MARK: - Private Methods
    
    private func setupMotionManager() {
        motionManager.deviceMotionUpdateInterval = sensorUpdateInterval
    }
    
    private func processMotionUpdate(_ motion: CMDeviceMotion) {
        let timestamp = motion.timestamp
        
        // Process accelerometer for step detection
        processAccelerometer(motion.userAcceleration, timestamp: timestamp)
        
        // Process gyroscope for bearing
        processGyroscope(motion.rotationRate, timestamp: timestamp)
        
        // Update state
        updateIMUState()
    }
    
    private func processAccelerometer(_ acceleration: CMAcceleration, timestamp: TimeInterval) {
        // Calculate magnitude (vertical component is most important for step detection)
        let magnitude = sqrt(acceleration.x * acceleration.x +
                            acceleration.y * acceleration.y +
                            acceleration.z * acceleration.z)
        
        // Log sample
        accelerationLogger.addSample(AccelerationSample(
            timestamp: Date(),
            x: acceleration.x,
            y: acceleration.y,
            z: acceleration.z,
            magnitude: magnitude,
            filtered: applyButterworthFilter(magnitude)
        ))
        
        // Apply filter
        let filtered = applyButterworthFilter(magnitude)
        filteredAcceleration.append(filtered)
        
        // Keep window size
        if filteredAcceleration.count > dynamicWindowSize {
            filteredAcceleration.removeFirst()
        }
        
        // Calculate variance
        if filteredAcceleration.count >= 3 {
            let variance = calculateVariance(filteredAcceleration.suffix(3))
            accelerationVariances.append(variance)
            if accelerationVariances.count > dynamicWindowSize {
                accelerationVariances.removeFirst()
            }
        }
        
        // Detect steps
        detectStep(filtered: filtered, timestamp: timestamp)
    }
    
    private func processGyroscope(_ rotationRate: CMRotationRate, timestamp: TimeInterval) {
        guard initialBearingSet else { return }
        
        if lastTimestamp != 0 {
            let dt = timestamp - lastTimestamp
            let gyroZ = rotationRate.z
            
            if abs(gyroZ) >= gyroNoiseThreshold && abs(gyroZ) <= maxGyroRate {
                // Integrate gyroscope for bearing (negative because iOS uses different convention)
                let deltaBearing = gyroZ * dt * (-180.0 / .pi)
                gyroIntegrationBearing = (gyroIntegrationBearing + deltaBearing).truncatingRemainder(dividingBy: 360)
                if gyroIntegrationBearing < 0 {
                    gyroIntegrationBearing += 360
                }
                
                // Apply bearing correction if available
                let result = applyBearingCorrection(gyroIntegrationBearing)
                currentBearing = result.bearing
            }
        }
        
        lastTimestamp = timestamp
    }
    
    private func detectStep(filtered: Double, timestamp: TimeInterval) {
        // Need enough data
        guard filteredAcceleration.count >= dynamicWindowSize else { return }
        
        // Simple peak detection
        let recentValues = Array(filteredAcceleration.suffix(5))
        guard recentValues.count >= 5 else { return }
        
        let current = recentValues[2]
        let isPeak = current > recentValues[0] &&
                     current > recentValues[1] &&
                     current > recentValues[3] &&
                     current > recentValues[4] &&
                     current > 0.1 // Minimum threshold
        
        if isPeak {
            let now = Date()
            
            // Check minimum time between steps (avoid double counting)
            if let lastStep = lastStepTime {
                let timeSinceLastStep = now.timeIntervalSince(lastStep)
                
                // Valid step period: 0.3s - 1.5s (40-200 steps/min)
                if timeSinceLastStep >= 0.3 && timeSinceLastStep <= 1.5 {
                    // Valid step detected
                    stepCount += 1
                    
                    // Update step period tracking
                    recentStepPeriods.append(timeSinceLastStep)
                    if recentStepPeriods.count > 10 {
                        recentStepPeriods.removeFirst()
                    }
                    
                    // Calculate step length using Weinberg method
                    let peakValleyDiff = abs(current - (recentValues.min() ?? 0))
                    let beta = stepFactorCalibration.isCalibrationValid() ? stepFactorCalibration.getUserBeta() : defaultBeta
                    currentStepLength = beta * pow(peakValleyDiff, 0.25)
                    
                    // Clamp step length to reasonable range
                    currentStepLength = min(max(currentStepLength, 0.3), 1.2)
                    
                    // Update position
                    updatePosition()
                    
                    // Add calibration data if calibrating
                    if stepFactorCalibration.isCalibrating {
                        stepFactorCalibration.addStepData(peakValleyDifference: peakValleyDiff)
                    }
                    
                    detectedPeaks.append(current)
                    if detectedPeaks.count > 10 {
                        detectedPeaks.removeFirst()
                    }
                }
            }
            
            lastStepTime = now
        }
    }
    
    private func updatePosition() {
        // Convert bearing to radians (using geographic convention: 0° = North, clockwise)
        let bearingRad = currentBearing * .pi / 180.0
        
        // Update position based on step and bearing
        currentX += currentStepLength * sin(bearingRad)
        currentY += currentStepLength * cos(bearingRad)
    }
    
    private func applyButterworthFilter(_ value: Double) -> Double {
        filterBuffer.append(value)
        
        // Keep buffer size limited
        if filterBuffer.count > 10 {
            filterBuffer.removeFirst()
        }
        
        // Simple moving average as approximation when not enough samples
        guard filterBuffer.count >= 3 else {
            return value
        }
        
        // Simple low-pass filter
        let sum = filterBuffer.suffix(3).reduce(0, +)
        return sum / 3.0
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
    
    private func calculateVariance(_ values: ArraySlice<Double>) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let sumSquaredDiff = values.reduce(0) { $0 + pow($1 - mean, 2) }
        return sumSquaredDiff / Double(values.count)
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
        
        imuState = IMUState(
            position: getCurrentPosition(),
            stepCount: stepCount,
            isCalibrated: calibrationManager?.isCalibrationValid() ?? false,
            accelerationMagnitude: Float(filteredAcceleration.last ?? 0),
            isMoving: isMoving,
            currentStepLength: currentStepLength,
            filterQuality: filterQuality,
            userBeta: stepFactorCalibration.getUserBeta(),
            isStepCalibrationValid: stepFactorCalibration.isCalibrationValid(),
            isStepCalibrating: stepFactorCalibration.isCalibrating
        )
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
    
    private let calibrationDistance: Double = 20.0 // meters
    private let defaultBeta: Double = 0.6
    
    func startCalibration() {
        isCalibrating = true
        userStepCount = 0
        accumulatedAccelerationDiff = 0
        print("UserStepFactorCalibration: Started - walk exactly 20 meters")
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
            }
        }
        
        isCalibrating = false
    }
    
    func stopCalibration() -> Bool {
        guard isCalibrating else { return false }
        
        if accumulatedAccelerationDiff > 0 && userStepCount > 0 {
            // Estimate based on partial data
            let avgStepAccDiff = accumulatedAccelerationDiff / Double(userStepCount)
            let estimatedDistance = Double(userStepCount) * 0.65 // Assume average step
            userBeta = estimatedDistance / accumulatedAccelerationDiff
            isValid = userBeta > 0.1 && userBeta < 2.0
            
            if isValid {
                calibratedBeta = userBeta
            }
        }
        
        isCalibrating = false
        return isValid
    }
    
    func getUserBeta() -> Double {
        return isValid ? calibratedBeta : defaultBeta
    }
    
    func isCalibrationValid() -> Bool {
        return isValid
    }
}

// MARK: - Acceleration Logger

class AccelerationLogger {
    private var samples: [AccelerationSample] = []
    private let maxSamples = 1000
    
    func addSample(_ sample: AccelerationSample) {
        samples.append(sample)
        if samples.count > maxSamples {
            samples.removeFirst()
        }
    }
    
    func getSamples() -> [AccelerationSample] {
        return samples
    }
    
    func clear() {
        samples.removeAll()
    }
}
