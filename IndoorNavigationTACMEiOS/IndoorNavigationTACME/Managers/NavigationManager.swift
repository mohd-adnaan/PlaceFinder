//
//  NavigationManager.swift
//  IndoorNavigationTACME
//
//  Core navigation manager with smart QR synchronization
//

import Foundation
import Combine
import UIKit

/// Core navigation manager coordinating all navigation components
class NavigationManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var navigationState = NavigationState()
    @Published var poiNames: [String] = []
    
    // MARK: - Private Properties
    
    private var calibrationManager: IMUCalibrationManager?
    private var sensorManager: IMUSensorManager?
    private var ttsManager: TTSManager?
    private var qrDetector: QRCodeDetector?
    private var languageManager: LanguageManager?
    
    // Session management
    private var sessionId: String = "ios_session_\(Int(Date().timeIntervalSince1970 * 1000))"
    
    // Update task
    private var updateTask: Task<Void, Never>?
    private var qrMonitoringTask: Task<Void, Never>?
    
    // Calibration data
    private var tempCalibrationData: CalibrationData?
    
    // Smart QR Sync State
    private var currentQRId: String?
    private var currentQRDetectionTime: Date?
    private var lastSentQRId: String?
    private let qrPersistenceWindow: TimeInterval = 3.0
    private let qrChangeDetectionWindow: TimeInterval = 0.2
    
    // Bearing correction
    private var pathBearings: [Double] = []
    private var currentSegmentId: Int = -1
    private var bearingCorrectionCount: Int = 0
    private let bearingCorrectionThreshold: Double = 25.0
    
    // Constants
    private let updateIntervalMs: UInt64 = 50
    private let maxRetryAttempts = 3
    private let retryDelayMs: UInt64 = 2000
    
    // Step tracking
    private var lastStepCount: Int = 0
    
    // MARK: - Initialization
    
    init() {
        print("NavigationManager: Initialized")
    }
    
    // MARK: - Configuration
    
    /// Configure manager dependencies
    func configure(
        calibrationManager: IMUCalibrationManager,
        sensorManager: IMUSensorManager,
        ttsManager: TTSManager,
        qrDetector: QRCodeDetector,
        languageManager: LanguageManager
    ) {
        self.calibrationManager = calibrationManager
        self.sensorManager = sensorManager
        self.ttsManager = ttsManager
        self.qrDetector = qrDetector
        self.languageManager = languageManager
        
        calibrationManager.setSensorManager(sensorManager)
        print("NavigationManager: Dependencies configured")
    }
    
    /// Set available POI names
    func setPOINames(_ names: [String]) {
        poiNames = names
        print("NavigationManager: Set \(names.count) POI names")
    }
    
    // MARK: - Navigation Control
    
    /// Initialize navigation with server
    func initializeWithServer(
        source: String,
        destination: String,
        useClockDirections: Bool,
        useLandmarks: Bool,
        conversationMode: Bool = false
    ) async -> Result<Void, Error> {
        print("NavigationManager: Initializing with server")
        print("  Source: \(source)")
        print("  Destination: \(destination)")
        
        navigationState.initializationStep = .notStarted
        
        let request = InitializeRequest(
            source: source,
            destination: destination,
            useClockDirections: useClockDirections,
            useLandmarks: useLandmarks,
            conversationMode: conversationMode
        )
        
        do {
            let response = try await NavigationAPIService.shared.initialize(request: request)
            
            guard response.status == "success" else {
                throw NavigationError.serverError(response.message ?? "Unknown error")
            }
            
            // Store calibration data
            if let calibration = response.calibration {
                tempCalibrationData = calibration
                print("NavigationManager: Received calibration data")
                print("  Start position: (\(calibration.mapStartX), \(calibration.mapStartY))")
                if let bearing = calibration.initialBearing {
                    print("  Initial bearing: \(bearing)°")
                }
            }
            
            // Store path bearings for bearing correction
            if let bearings = response.pathBearings {
                storePathBearings(bearings)
            }
            
            await MainActor.run {
                navigationState.isInitialized = true
                navigationState.source = source
                navigationState.destination = destination
                navigationState.useClockDirections = useClockDirections
                navigationState.useLandmarks = useLandmarks
                navigationState.initializationStep = .initialized
                navigationState.currentInstruction = response.message ?? "Server connected! Ready to start navigation."
                navigationState.lastUpdateTime = Date()
            }
            
            // Announce readiness
            let message = languageManager?.getString("Server connected! Ready to start navigation.") ??
                         "Server connected! Ready to start navigation."
            ttsManager?.speak(message, force: true)
            
            return .success(())
            
        } catch {
            print("NavigationManager: Initialization failed: \(error)")
            await MainActor.run {
                navigationState.initializationStep = .error
                navigationState.errorMessage = "Connection error: \(error.localizedDescription)"
            }
            return .failure(error)
        }
    }
    
    /// Start navigation with calibration
    func startNavigationWithCalibration() async -> Result<Void, Error> {
        print("NavigationManager: Starting navigation with calibration")
        
        guard navigationState.isInitialized else {
            return .failure(NavigationError.notInitialized)
        }
        
        guard let calibration = tempCalibrationData else {
            return .failure(NavigationError.noCalibrationData)
        }
        
        // Reset sensors
        sensorManager?.resetPosition()
        
        // Wait for sensor reset
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Get current IMU position
        guard let currentPosition = sensorManager?.getCurrentPosition() else {
            return .failure(NavigationError.sensorError)
        }
        
        // Perform calibration
        let success = calibrationManager?.calibrateWithMapPosition(
            currentImuPosition: currentPosition,
            mapX: calibration.mapStartX,
            mapY: calibration.mapStartY,
            mapBearing: calibration.initialBearing,
            stepCount: 0
        ) ?? false
        
        guard success else {
            return .failure(NavigationError.calibrationFailed)
        }
        
        // Start navigation
        await MainActor.run {
            navigationState.isNavigating = true
            navigationState.isCalibrated = true
            navigationState.initializationStep = .navigating
            navigationState.currentInstruction = "Navigation started"
        }
        
        // Start QR detection
        startQRDetection()
        
        // Start position update loop
        startPositionUpdates()
        
        // Announce start
        let message = languageManager?.getString("navigation started") ?? "Navigation started"
        ttsManager?.speak(message, force: true)
        
        return .success(())
    }
    
    /// Stop navigation
    func stopNavigation() {
        print("NavigationManager: Stopping navigation")
        
        // Cancel update tasks
        updateTask?.cancel()
        updateTask = nil
        qrMonitoringTask?.cancel()
        qrMonitoringTask = nil
        
        // Stop QR detection
        qrDetector?.stopScanning()
        
        // Reset QR sync state
        resetQRSyncState()
        
        // Update state
        navigationState.isNavigating = false
        navigationState.isInitialized = false
        navigationState.isCalibrated = false
        navigationState.currentInstruction = "Navigation stopped"
        navigationState.initializationStep = .notStarted
        navigationState.errorMessage = nil
        navigationState.qrDetectionActive = false
        navigationState.qrSyncMode = "DISABLED"
        
        // Announce stop
        ttsManager?.speakPriority("Navigation stopped")
        
        // Reset sensors and calibration
        sensorManager?.resetPosition()
        calibrationManager?.resetCalibration()
        tempCalibrationData = nil
    }
    
    /// Force a position update
    func forcePositionUpdate() async -> Result<String, Error> {
        guard let mapPosition = sensorManager?.getCurrentMapPosition() else {
            return .failure(NavigationError.sensorError)
        }
        
        let (qrDetected, qrId) = getSmartQRState()
        
        let request = UpdateRequest(
            currentX: mapPosition.x,
            currentY: mapPosition.y,
            currentBearing: mapPosition.bearing,
            qrDetected: qrDetected,
            qrCodeId: qrId
        )
        
        do {
            let response = try await NavigationAPIService.shared.updatePosition(request: request)
            
            if let instruction = response.instructions {
                await MainActor.run {
                    navigationState.currentInstruction = instruction
                    navigationState.lastUpdateTime = Date()
                }
                return .success(instruction)
            }
            
            return .failure(NavigationError.noInstruction)
        } catch {
            return .failure(error)
        }
    }
    
    /// Test QR detection system
    func testQRDetection() {
        print("NavigationManager: Testing QR detection system")
        qrDetector?.testVisionCapabilities()
        print("QR Stats: \(qrDetector?.getDetectionStats() ?? [:])")
        print("Smart QR Info: \(getSmartQRInfo())")
    }
    
    /// Resume QR detection (called from app resume)
    func resumeQRDetection() {
        if navigationState.isNavigating && navigationState.qrDetectionActive {
            qrDetector?.startScanning()
        }
    }
    
    /// Get comprehensive smart QR state information
    func getSmartQRInfo() -> [String: Any] {
        let qrState = qrDetector?.detectionState
        let (smartDetected, smartId) = getSmartQRState()
        
        return [
            "cameraDetected": qrState?.isDetected ?? false,
            "cameraContent": qrState?.lastQRContent ?? "None",
            "smartDetected": smartDetected,
            "smartId": smartId ?? "None",
            "currentQRId": currentQRId ?? "None",
            "lastSentQRId": lastSentQRId ?? "None",
            "qrDetectionCount": navigationState.qrDetectionCount,
            "qrEngine": "VISION",
            "qrSyncMode": navigationState.qrSyncMode
        ]
    }
    
    /// Cleanup resources
    func cleanup() {
        print("NavigationManager: Cleaning up")
        updateTask?.cancel()
        qrMonitoringTask?.cancel()
        qrDetector?.cleanup()
        resetQRSyncState()
    }
    
    // MARK: - Private Methods
    
    private func startQRDetection() {
        qrDetector?.startScanning()
        navigationState.qrDetectionActive = true
        navigationState.qrSyncMode = "SMART_SYNC"
        
        // Start QR monitoring task
        startSmartQRMonitoring()
        
        print("NavigationManager: QR detection started")
    }
    
    private func startPositionUpdates() {
        updateTask?.cancel()
        
        updateTask = Task {
            while !Task.isCancelled && navigationState.isNavigating {
                await performPositionUpdate()
                try? await Task.sleep(nanoseconds: updateIntervalMs * 1_000_000)
            }
        }
    }
    
    private func performPositionUpdate() async {
        guard let sensorManager = sensorManager,
              let mapPosition = sensorManager.getCurrentMapPosition() else {
            return
        }
        
        // Check for new steps
        let currentSteps = sensorManager.imuState.stepCount
        guard currentSteps > lastStepCount else { return }
        
        lastStepCount = currentSteps
        
        // Get smart QR state
        let (qrDetected, qrId) = getSmartQRState()
        
        // Track sent QR
        if qrDetected && qrId != nil {
            lastSentQRId = qrId
            await MainActor.run {
                navigationState.lastSentQRId = qrId
            }
        }
        
        let request = UpdateRequest(
            currentX: mapPosition.x,
            currentY: mapPosition.y,
            currentBearing: mapPosition.bearing,
            qrDetected: qrDetected,
            qrCodeId: qrId
        )
        
        do {
            let response = try await NavigationAPIService.shared.updatePosition(request: request)
            await handleNavigationResponse(response)
        } catch {
            print("NavigationManager: Update error: \(error)")
        }
    }
    
    private func handleNavigationResponse(_ response: NavigationResponse) async {
        // Handle segment info
        if let segmentInfo = response.segmentInfo {
            updateCurrentSegmentId(segmentInfo.segmentIndex)
        }
        
        // Handle recalibration
        if let newPosition = response.newMapPosition, newPosition.count >= 2 {
            await handleRecalibration(
                newPosition: newPosition,
                reason: response.deviationType ?? "position_update"
            )
        }
        
        // Handle instructions
        if let instruction = response.instructions {
            let translatedInstruction: String
            if languageManager?.isFrench() == true {
                translatedInstruction = await languageManager?.translateFromEnglish(instruction) ?? instruction
            } else {
                translatedInstruction = instruction
            }
            
            await MainActor.run {
                navigationState.currentInstruction = translatedInstruction
                navigationState.serverResponse = response.message
                navigationState.lastUpdateTime = Date()
            }
            
            // Announce instruction
            handleInstructionAnnouncement(translatedInstruction)
        }
    }
    
    private func handleInstructionAnnouncement(_ instruction: String) {
        let lowerInstruction = instruction.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Skip certain phrases
        let skipPhrases = [
            "continue moving",
            "keep going",
            "you're on track",
            "on the right path"
        ]
        
        if skipPhrases.contains(where: { lowerInstruction.contains($0) }) {
            return
        }
        
        // Use appropriate speech method based on instruction type
        if ttsManager?.isEmergencyCorrection(instruction) == true {
            ttsManager?.speakEmergencyCorrection(instruction)
        } else {
            ttsManager?.speak(instruction)
        }
    }
    
    private func handleRecalibration(newPosition: [Double], reason: String) async {
        guard newPosition.count >= 2 else { return }
        
        let mapX = newPosition[0]
        let mapY = newPosition[1]
        
        // Determine bearing handling based on reason
        let mapBearing: Double?
        switch reason {
        case "segment_ending":
            mapBearing = sensorManager?.getCurrentMapPosition()?.bearing
        case "segment_change":
            mapBearing = sensorManager?.getCurrentMapPosition()?.bearing
        default:
            mapBearing = sensorManager?.getCurrentMapPosition()?.bearing
        }
        
        print("NavigationManager: Recalibrating - \(reason)")
        
        // Reset IMU position
        sensorManager?.resetPosition()
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        guard let resetPosition = sensorManager?.getCurrentPosition() else { return }
        
        let success = calibrationManager?.calibrateWithMapPosition(
            currentImuPosition: resetPosition,
            mapX: mapX,
            mapY: mapY,
            mapBearing: mapBearing,
            stepCount: sensorManager?.imuState.stepCount ?? 0
        ) ?? false
        
        if success {
            print("NavigationManager: Recalibration successful")
        } else {
            print("NavigationManager: Recalibration failed")
        }
    }
    
    private func startSmartQRMonitoring() {
        qrMonitoringTask?.cancel()
        
        qrMonitoringTask = Task {
            while !Task.isCancelled && navigationState.isNavigating {
                await checkQRState()
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
    }
    
    private func checkQRState() async {
        guard let qrState = qrDetector?.detectionState,
              qrState.isDetected,
              let content = qrState.lastQRContent,
              let numericId = QRIdExtractor.extractQRCodeId(content) else {
            return
        }
        
        let isNewQR = numericId != currentQRId
        
        if isNewQR {
            print("NavigationManager: QR Change - \(currentQRId ?? "none") → \(numericId)")
            currentQRId = numericId
            currentQRDetectionTime = Date()
            
            await MainActor.run {
                navigationState.currentQRId = numericId
                navigationState.lastQRDetectionTime = Date()
                navigationState.qrDetectionCount += 1
            }
        } else {
            currentQRDetectionTime = Date()
        }
    }
    
    private func getSmartQRState() -> (Bool, String?) {
        let currentTime = Date()
        
        // Check for immediate detection
        if let qrState = qrDetector?.detectionState,
           qrState.isDetected,
           let content = qrState.lastQRContent,
           let newQRId = QRIdExtractor.extractQRCodeId(content) {
            
            if newQRId != currentQRId {
                print("NavigationManager: New QR - \(currentQRId ?? "none") → \(newQRId)")
                currentQRId = newQRId
                currentQRDetectionTime = currentTime
                
                DispatchQueue.main.async {
                    self.navigationState.currentQRId = newQRId
                    self.navigationState.lastQRDetectionTime = currentTime
                    self.navigationState.qrDetectionCount += 1
                }
                
                return (true, newQRId)
            } else {
                currentQRDetectionTime = currentTime
                return (true, newQRId)
            }
        }
        
        // Check persistent QR
        if let qrId = currentQRId, let detectionTime = currentQRDetectionTime {
            let timeSince = currentTime.timeIntervalSince(detectionTime)
            if timeSince < qrPersistenceWindow {
                return (true, qrId)
            } else {
                currentQRId = nil
                currentQRDetectionTime = nil
                DispatchQueue.main.async {
                    self.navigationState.currentQRId = nil
                }
            }
        }
        
        return (false, nil)
    }
    
    private func resetQRSyncState() {
        currentQRId = nil
        currentQRDetectionTime = nil
        lastSentQRId = nil
        
        navigationState.currentQRId = nil
        navigationState.lastSentQRId = nil
        navigationState.qrDetectionCount = 0
        navigationState.lastQRDetectionTime = nil
        
        print("NavigationManager: QR sync state reset")
    }
    
    private func storePathBearings(_ bearings: [Double]) {
        pathBearings = bearings
        sensorManager?.setBearingCorrectionData(bearings, currentSegmentId)
        print("NavigationManager: Stored \(bearings.count) path bearings")
    }
    
    private func updateCurrentSegmentId(_ segmentId: Int) {
        guard segmentId != currentSegmentId else { return }
        
        currentSegmentId = segmentId
        sensorManager?.setBearingCorrectionData(pathBearings, segmentId)
        
        navigationState.currentSegmentId = segmentId
        
        print("NavigationManager: Segment updated to \(segmentId)")
    }
}

// MARK: - Errors

enum NavigationError: LocalizedError {
    case notInitialized
    case noCalibrationData
    case calibrationFailed
    case sensorError
    case serverError(String)
    case noInstruction
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Navigation not initialized"
        case .noCalibrationData:
            return "No calibration data received"
        case .calibrationFailed:
            return "Calibration failed"
        case .sensorError:
            return "Sensor error"
        case .serverError(let message):
            return "Server error: \(message)"
        case .noInstruction:
            return "No instruction received"
        }
    }
}
