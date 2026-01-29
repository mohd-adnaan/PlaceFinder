//
//  IMUSensorManager.swift
//  IndoorNavigationTACME
//
//  Core IMU sensor processing - CoreMotion implementation
//  FIXED: All 7 compilation errors resolved
//

import Foundation
import CoreMotion
import Combine

/// Manager for IMU sensor processing and step detection
class IMUSensorManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var imuState = IMUState(
        position: Position(),
        stepCount: 0,
        isCalibrated: false,
        accelerationMagnitude: 0,
        isMoving: false,
        currentStepLength: 0.65,
        filterQuality: "Initializing",
        beta: 0.6,
        isStepCalibrationValid: false,
        isCalibrating: false,
        calibrationStepCount: 0,
        bearing: 0
    )
    
    // MARK: - Private Properties
    
    private let motionManager = CMMotionManager()
    private var calibrationManager: IMUCalibrationManager?
    
    // Step detection
    private var stepCount: Int = 0
    private var lastStepTime: Date?
    private var currentStepLength: Double = 0.65
    private var recentStepPeriods: [TimeInterval] = []
    
    // Acceleration processing
    private var filteredAcceleration: [Double] = []
    private var accelerationVariances: [Double] = []  // FIX 1: Added missing property
    private var detectedPeaks: [Double] = []          // FIX 2: Added missing property
    private var filterBuffer: [Double] = []           // FIX 3: Added missing property
    private var lastPeak: Double = 0
    private var lastValley: Double = 0
    private var peakConfirmed = false
    private var valleyConfirmed = false
    private let filterOrder = 4
    private let filterWindowSize = 10
    
    // Position tracking
    private var currentPosition = Position()
    private var currentBearing: Double = 0
    
    // Step factor calibration
    private let stepFactorCalibration = UserStepFactorCalibration()
    
    // Bearing correction
    private var pathBearings: [Double] = []
    private var currentSegmentId: Int = -1
    
    // Constants
    private let updateInterval: TimeInterval = 0.02 // 50Hz
    private let stepThreshold: Double = 0.15
    private let minStepInterval: TimeInterval = 0.25
    private let maxStepInterval: TimeInterval = 2.0
    
    // MARK: - Initialization
    
    init() {
        print("IMUSensorManager: Initialized")
    }
    
    // MARK: - Configuration
    
    /// Set calibration manager reference
    func setCalibrationManager(_ manager: IMUCalibrationManager) {
        self.calibrationManager = manager
        print("IMUSensorManager: Calibration manager set")
    }
    
    // MARK: - Public Methods
    
    /// Start sensor updates
    func startSensors() {
        guard motionManager.isDeviceMotionAvailable else {
            print("IMUSensorManager: Device motion not available")
            return
        }
        
        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: .main
        ) { [weak self] motion, error in
            guard let self = self, let motion = motion else {
                if let error = error {
                    print("IMUSensorManager: Motion update error: \(error)")
                }
                return
            }
            self.processMotionUpdate(motion)
        }
        
        print("IMUSensorManager: Started updates at \(1/updateInterval)Hz")
    }
    
    /// Stop sensor updates
    func stopSensors() {
        motionManager.stopDeviceMotionUpdates()
        print("IMUSensorManager: Stopped updates")
    }
    
    /// Get current position transformed to map coordinates
    func getCurrentMapPosition() -> Position? {
        return calibrationManager?.transformToMapPosition(getCurrentPosition())
    }
    
    /// Reset position to origin
    func resetPosition() {
        stepCount = 0
        currentPosition = Position()
        currentBearing = 0
        filteredAcceleration.removeAll()
        accelerationVariances.removeAll()
        detectedPeaks.removeAll()
        filterBuffer.removeAll()
        lastPeak = 0
        lastValley = 0
        peakConfirmed = false
        valleyConfirmed = false
        recentStepPeriods.removeAll()
        
        updateState()
        print("IMUSensorManager: Position reset")
    }
    
    /// Get current position
    func getCurrentPosition() -> Position {
        return currentPosition
    }
    
    /// Set initial bearing from calibration
    func setInitialBearing(_ bearing: Double) {
        currentBearing = bearing
        currentPosition = Position(x: currentPosition.x, y: currentPosition.y, bearing: bearing)
        print("IMUSensorManager: Initial bearing set to \(bearing)°")
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
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.imuState.isCalibrating = true
            self.imuState.calibrationStepCount = 0
        }
        print("IMUSensorManager: Step calibration started")
    }
    
    /// Complete step calibration
    func completeStepCalibration() {
        stepFactorCalibration.completeCalibration()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.imuState.beta = self.stepFactorCalibration.getUserBeta()
            self.imuState.isStepCalibrationValid = self.stepFactorCalibration.isCalibrationValid()
            self.imuState.isCalibrating = false
        }
        print("IMUSensorManager: Step calibration completed - beta: \(stepFactorCalibration.getUserBeta())")
    }
    
    /// Stop step calibration
    func stopStepCalibration() {
        let _ = stepFactorCalibration.stopCalibration()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.imuState.beta = self.stepFactorCalibration.getUserBeta()
            self.imuState.isStepCalibrationValid = self.stepFactorCalibration.isCalibrationValid()
            self.imuState.isCalibrating = false
        }
        print("IMUSensorManager: Step calibration stopped")
    }
    
    /// Cancel step calibration
    func cancelStepCalibration() {
        stepFactorCalibration.cancel()
        
        DispatchQueue.main.async { [weak self] in
            self?.imuState.isCalibrating = false
        }
    }
    
    // MARK: - Debug Methods
    
    /// Get step detection metrics
    func getStepDetectionMetrics() -> [String: Any] {
        return [
            "totalSteps": stepCount,
            "averageStepLength": String(format: "%.2f", currentStepLength),
            "recentStepPeriods": recentStepPeriods.suffix(5),
            "currentBearing": String(format: "%.1f", currentBearing),
            "filterQuality": getFilterQuality()
        ]
    }
    
    /// Clear accumulated sensor data
    func clearAccumulatedData() {
        filteredAcceleration.removeAll()
        accelerationVariances.removeAll()
        detectedPeaks.removeAll()
        recentStepPeriods.removeAll()
        filterBuffer.removeAll()
        print("IMUSensorManager: Accumulated data cleared")
    }
    
    // MARK: - Private Methods
    
    private func processMotionUpdate(_ motion: CMDeviceMotion) {
        // Get vertical acceleration
        let gravity = motion.gravity
        let userAccel = motion.userAcceleration
        
        // Project user acceleration onto vertical axis
        let verticalAccel = userAccel.x * gravity.x + userAccel.y * gravity.y + userAccel.z * gravity.z
        
        // Apply low-pass filter (Butterworth approximation)
        filteredAcceleration.append(verticalAccel)
        if filteredAcceleration.count > filterWindowSize {
            filteredAcceleration.removeFirst()
        }
        
        let filteredValue = applyLowPassFilter()
        
        // Update bearing from gyroscope
        // iOS gyroscope Z-axis is inverted compared to Android
        let gyroZ = motion.rotationRate.z
        currentBearing += gyroZ * updateInterval * (-180.0 / .pi)
        
        // Normalize bearing to 0-360
        while currentBearing < 0 { currentBearing += 360 }
        while currentBearing >= 360 { currentBearing -= 360 }
        
        // Detect steps
        detectStep(filteredValue)
        
        // Update state - FIX 4: Cast to Float explicitly
        updateState(accelerationMagnitude: Float(abs(filteredValue)))
    }
    
    private func applyLowPassFilter() -> Double {
        guard filteredAcceleration.count >= 2 else {
            return filteredAcceleration.last ?? 0
        }
        
        // Simple exponential moving average as Butterworth approximation
        let alpha = 0.3
        var result = filteredAcceleration[0]
        for value in filteredAcceleration.dropFirst() {
            result = alpha * value + (1 - alpha) * result
        }
        return result
    }
    
    private func detectStep(_ acceleration: Double) {
        let currentTime = Date()
        
        // Peak detection
        if acceleration > lastPeak {
            lastPeak = acceleration
            peakConfirmed = false
        } else if !peakConfirmed && lastPeak - acceleration > stepThreshold {
            peakConfirmed = true
        }
        
        // Valley detection
        if acceleration < lastValley {
            lastValley = acceleration
            valleyConfirmed = false
        } else if !valleyConfirmed && acceleration - lastValley > stepThreshold {
            valleyConfirmed = true
        }
        
        // Confirm step when both peak and valley detected
        if peakConfirmed && valleyConfirmed {
            let peakValleyDiff = lastPeak - lastValley
            
            // Validate step timing
            var isValidStep = true
            if let lastTime = lastStepTime {
                let timeSinceLastStep = currentTime.timeIntervalSince(lastTime)
                isValidStep = timeSinceLastStep >= minStepInterval && timeSinceLastStep <= maxStepInterval
            }
            
            if isValidStep && peakValleyDiff > stepThreshold {
                // Record step period
                if let lastTime = lastStepTime {
                    let stepPeriod = currentTime.timeIntervalSince(lastTime)
                    recentStepPeriods.append(stepPeriod)
                    if recentStepPeriods.count > 10 {
                        recentStepPeriods.removeFirst()
                    }
                }
                
                // Calculate step length using Weinberg method
                currentStepLength = calculateStepLength(peakValleyDiff)
                
                // Update calibration data if calibrating
                if stepFactorCalibration.isCalibrating {
                    stepFactorCalibration.addStepData(peakValleyDifference: peakValleyDiff)
                    
                    // Update UI for real-time calibration feedback
                    DispatchQueue.main.async { [weak self] in
                        self?.imuState.calibrationStepCount = self?.stepFactorCalibration.getStepCount() ?? 0
                    }
                }
                
                // Update step count and position
                stepCount += 1
                lastStepTime = currentTime
                updatePositionFromStep()
                
                // FIX 5: Notify calibration manager with correct argument labels
                calibrationManager?.updateCalibration(
                    currentImuPosition: getCurrentPosition(),
                    stepCount: stepCount
                )
            }
            
            // Reset for next step detection
            lastPeak = acceleration
            lastValley = acceleration
            peakConfirmed = false
            valleyConfirmed = false
        }
    }
    
    private func calculateStepLength(_ peakValleyDiff: Double) -> Double {
        let beta = stepFactorCalibration.getUserBeta()
        return beta * pow(peakValleyDiff, 0.25)
    }
    
    private func updatePositionFromStep() {
        let bearingRad = currentBearing * .pi / 180.0
        currentPosition = Position(
            x: currentPosition.x + currentStepLength * sin(bearingRad),
            y: currentPosition.y + currentStepLength * cos(bearingRad),
            bearing: currentBearing
        )
    }
    
    private func updateState(accelerationMagnitude: Float = 0) {
        let isMoving = recentStepPeriods.count > 0 &&
                      (lastStepTime.map { Date().timeIntervalSince($0) < 2.0 } ?? false)
        
        // FIX 6: Use isCalibrationValid() instead of isCalibrated
        let isCalibrated = calibrationManager?.isCalibrationValid() ?? false
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.imuState = IMUState(
                position: self.currentPosition,
                stepCount: self.stepCount,
                isCalibrated: isCalibrated,
                accelerationMagnitude: accelerationMagnitude,
                isMoving: isMoving,
                currentStepLength: self.currentStepLength,
                filterQuality: self.getFilterQuality(),
                beta: self.stepFactorCalibration.getUserBeta(),
                isStepCalibrationValid: self.stepFactorCalibration.isCalibrationValid(),
                isCalibrating: self.stepFactorCalibration.isCalibrating,
                calibrationStepCount: self.stepFactorCalibration.getStepCount(),
                bearing: self.currentBearing
            )
        }
    }
    
    private func getFilterQuality() -> String {
        let sampleCount = filteredAcceleration.count
        if sampleCount < 3 { return "Initializing" }
        if sampleCount < filterWindowSize / 2 { return "Warming Up" }
        if sampleCount < filterWindowSize { return "Good" }
        return "Excellent"
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
    
    func getStepCount() -> Int {
        return userStepCount
    }
    
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
        
        print("UserStepFactorCalibration: Step \(userStepCount) - accDiff: \(String(format: "%.3f", accDiff))")
    }
    
    func completeCalibration() {
        guard isCalibrating else { return }
        
        if accumulatedAccelerationDiff > 0 {
            userBeta = calibrationDistance / accumulatedAccelerationDiff
            isValid = userBeta > 0.1 && userBeta < 2.0
            
            if isValid {
                calibratedBeta = userBeta
                print("UserStepFactorCalibration: Complete - beta: \(String(format: "%.4f", userBeta)), steps: \(userStepCount)")
            } else {
                print("UserStepFactorCalibration: Result out of range - beta: \(String(format: "%.4f", userBeta))")
            }
        } else {
            print("UserStepFactorCalibration: Failed - insufficient data")
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
                print("UserStepFactorCalibration: Stopped early - beta: \(String(format: "%.4f", userBeta))")
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
    
    func cancel() {
        isCalibrating = false
        userStepCount = 0
        accumulatedAccelerationDiff = 0
        print("UserStepFactorCalibration: Cancelled")
    }
}
