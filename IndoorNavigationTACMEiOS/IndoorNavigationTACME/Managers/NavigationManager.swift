//
//  NavigationManager.swift
//  IndoorNavigationTACME
//
//

import Foundation
import Combine
import UIKit

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
    
    // Update tasks
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
    private var pathCoordinates: [[Double]] = []
    private var currentSegmentId: Int = -1
    private var bearingCorrectionCount: Int = 0
    private let bearingCorrectionThreshold: Double = 25.0
    
    // Step tracking
    private var lastStepCount: Int = 0
    private var lastInstructionText: String = ""
    private var lastInstructionTime: Date = Date.distantPast
    private var updateCount: Int = 0
    
    // Constants - MATCHING ANDROID
    private let updateIntervalMs: UInt64 = 50  // Android uses 50ms
    private let minInstructionInterval: TimeInterval = 1.5
    private let maxRetryAttempts = 3
    private let retryDelayMs: UInt64 = 2000
    
    // Retry tracking
    private var retryCount: Int = 0
    
    // MARK: - Init
    
    init() {
        print("NavigationManager: Initialized")
    }
    
    // MARK: - Configuration
    
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
        sensorManager.setCalibrationManager(calibrationManager)
        print("NavigationManager: Dependencies configured")
    }
    
    func setPOINames(_ names: [String]) {
        DispatchQueue.main.async {
            self.poiNames = names
        }
        print("NavigationManager: Set \(names.count) POI names")
    }
    
    // MARK: - Navigation Control
    
    func initializeWithServer(
        source: String,
        destination: String,
        useClockDirections: Bool,
        useLandmarks: Bool,
        conversationMode: Bool = false
    ) async -> Result<Void, Error> {
        print("")
        print("═══════════════════════════════════════════════════════")
        print("NavigationManager: Initializing with server")
        print("  Source: \(source)")
        print("  Destination: \(destination)")
        print("  Clock Directions: \(useClockDirections)")
        print("  Landmarks: \(useLandmarks)")
        print("═══════════════════════════════════════════════════════")
        
        await MainActor.run {
            navigationState.initializationStep = .connecting
            navigationState.errorMessage = nil
            navigationState.currentInstruction = "Connecting to server..."
        }
        
        sessionId = "ios_session_\(Int(Date().timeIntervalSince1970 * 1000))"
        await NavigationAPIService.shared.resetSession()
        
        let request = InitializeRequest(
            source: source,
            destination: destination,
            useClockDirections: useClockDirections,
            useLandmarks: useLandmarks,
            conversationMode: conversationMode
        )
        
        do {
            let response = try await NavigationAPIService.shared.initialize(request: request)
            
            print("NavigationManager: Response status: \(response.status)")
            print("NavigationManager: Message: \(response.message ?? "nil")")
            print("NavigationManager: Instructions: \(response.instructions ?? "nil")")
            
            guard response.status == "success" else {
                throw NSError(domain: "Nav", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: response.message ?? "Server initialization failed"
                ])
            }
            
            // Store calibration data
            if let calibration = response.calibration {
                tempCalibrationData = calibration
                print("NavigationManager: ✓ Calibration data: start=(\(calibration.mapStartX), \(calibration.mapStartY)), bearing=\(calibration.initialBearing ?? 0)°")
            }
            
            // Store path bearings for bearing correction (matching Android)
            if let bearings = response.pathBearings {
                pathBearings = bearings
                // Immediately provide to sensor manager
                sensorManager?.setBearingCorrectionData(bearings, currentSegmentId)
                print("NavigationManager: ✓ Stored \(bearings.count) path bearings")
            }
            
            if let coords = response.pathCoordinates {
                pathCoordinates = coords
                print("NavigationManager: ✓ Stored \(coords.count) path coordinates")
            }
            
            let serverMessage = response.instructions ?? response.message ?? "Server connected"
            
            await MainActor.run {
                navigationState.isInitialized = true
                navigationState.source = source
                navigationState.destination = destination
                navigationState.useClockDirections = useClockDirections
                navigationState.useLandmarks = useLandmarks
                navigationState.initializationStep = .initialized
                navigationState.serverResponse = serverMessage
                navigationState.currentInstruction = "Ready! Tap Start Navigation."
                navigationState.lastUpdateTime = Date()
                navigationState.errorMessage = nil
            }
            
            ttsManager?.speak("Server connected. Ready to start navigation.", force: true)
            return .success(())
            
        } catch {
            print("NavigationManager: ✗ Initialization failed: \(error)")
            await MainActor.run {
                navigationState.initializationStep = .error
                navigationState.errorMessage = error.localizedDescription
                navigationState.currentInstruction = "Connection failed: \(error.localizedDescription)"
            }
            ttsManager?.speakCritical("Connection failed")
            return .failure(error)
        }
    }
    
    func startNavigationWithCalibration() async -> Result<Void, Error> {
        print("")
        print("═══════════════════════════════════════════════════════")
        print("NavigationManager: Starting Navigation with Calibration")
        print("═══════════════════════════════════════════════════════")
        
        guard navigationState.isInitialized else {
            ttsManager?.speakCritical("Please initialize first")
            return .failure(NSError(domain: "Nav", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not initialized"]))
        }
        
        guard let calibration = tempCalibrationData else {
            ttsManager?.speakCritical("No calibration data from server")
            return .failure(NSError(domain: "Nav", code: -2, userInfo: [NSLocalizedDescriptionKey: "No calibration data"]))
        }
        
        // Reset sensors before calibration
        sensorManager?.resetPosition()
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms settle time
        
        // Get current IMU position after reset
        guard let currentImuPosition = sensorManager?.getCurrentPosition() else {
            return .failure(NSError(domain: "Nav", code: -3, userInfo: [NSLocalizedDescriptionKey: "Sensor error"]))
        }
        
        // Calibrate using map position from server
        let success = calibrationManager?.calibrateWithMapPosition(
            currentImuPosition: currentImuPosition,
            mapX: calibration.mapStartX,
            mapY: calibration.mapStartY,
            mapBearing: calibration.initialBearing,
            stepCount: sensorManager?.imuState.stepCount ?? 0
        ) ?? false
        
        if !success {
            print("NavigationManager: ✗ Calibration failed!")
            ttsManager?.speakCritical("Calibration failed")
            return .failure(NSError(domain: "Nav", code: -3, userInfo: [NSLocalizedDescriptionKey: "Calibration failed"]))
        }
        
        print("NavigationManager: ✓ Calibration successful")
        
        // Reset tracking state
        lastStepCount = sensorManager?.imuState.stepCount ?? 0
        lastInstructionText = ""
        lastInstructionTime = Date.distantPast
        updateCount = 0
        retryCount = 0
        
        // Update state ON MAIN THREAD
        await MainActor.run {
            navigationState.isCalibrated = true
            navigationState.isNavigating = true
            navigationState.initializationStep = .navigating
            navigationState.currentInstruction = "Starting navigation..."
            navigationState.qrDetectionActive = true
            navigationState.qrSyncMode = "SMART_SYNC"
        }
        
        // Start QR detection on main thread
        await MainActor.run {
            qrDetector?.startScanning()
        }
        
        let message = languageManager?.isFrench() == true
            ? (await languageManager?.translateFromEnglish("Navigation started") ?? "Navigation started")
            : "Navigation started"
        ttsManager?.speak(message, force: true)
        
        // Send first position update immediately at calibration point
        print("NavigationManager: Sending FIRST position update at calibration point...")
        await sendFirstPositionUpdate()
        
        // Start continuous update loop
        startPositionUpdateLoop()
        
        // Start QR monitoring
        startQRMonitoring()
        
        return .success(())
    }
    
    func stopNavigation() {
        print("NavigationManager: Stopping navigation")
        
        // Cancel tasks
        updateTask?.cancel()
        updateTask = nil
        qrMonitoringTask?.cancel()
        qrMonitoringTask = nil
        
        // Stop QR detection
        qrDetector?.stopScanning()
        
        // Reset QR state
        currentQRId = nil
        currentQRDetectionTime = nil
        lastSentQRId = nil
        
        // Update state
        DispatchQueue.main.async {
            self.navigationState.isNavigating = false
            self.navigationState.isInitialized = false
            self.navigationState.isCalibrated = false
            self.navigationState.currentInstruction = "Navigation stopped"
            self.navigationState.initializationStep = .notStarted
            self.navigationState.errorMessage = nil
            self.navigationState.qrDetectionActive = false
            self.navigationState.qrSyncMode = "DISABLED"
        }
        
        ttsManager?.speakPriority("Navigation stopped")
        
        // Reset sensors and calibration
        sensorManager?.resetPosition()
        calibrationManager?.resetCalibration()
        tempCalibrationData = nil
    }
    
    func forcePositionUpdate() async -> Result<String, Error> {
        guard let mapPosition = sensorManager?.getCurrentMapPosition() else {
            return .failure(NSError(domain: "Nav", code: -4, userInfo: [NSLocalizedDescriptionKey: "Sensor error"]))
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
            await handleNavigationResponse(response, isFirstUpdate: false)
            return .success(response.instructions ?? response.message ?? "OK")
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - Smart QR Sync (matching Android)
    
    private func getSmartQRState() -> (Bool, String?) {
        guard let qrId = currentQRId,
              let detectionTime = currentQRDetectionTime else {
            return (false, nil)
        }
        
        let elapsed = Date().timeIntervalSince(detectionTime)
        
        // Within persistence window
        if elapsed <= qrPersistenceWindow {
            // Don't re-send same QR unless it's a fresh detection
            if qrId == lastSentQRId && elapsed > qrChangeDetectionWindow {
                return (false, nil)
            }
            return (true, qrId)
        }
        
        // Expired
        currentQRId = nil
        currentQRDetectionTime = nil
        return (false, nil)
    }
    
    private func startQRMonitoring() {
        qrMonitoringTask?.cancel()
        qrMonitoringTask = Task {
            while !Task.isCancelled && navigationState.isNavigating {
                // Read QR state from the detector's published detectionState
                if let qrDetector = qrDetector,
                   qrDetector.detectionState.isDetected,
                   let rawContent = qrDetector.detectionState.detectedContent {
                    
                    // Extract the QR ID from raw content (e.g. "QR_Id:https://qrco.de/bgErvr" → "bgErvr")
                    let detectedId = QRIdExtractor.extractQRCodeId(rawContent) ?? rawContent
                    
                    let isNewQR = detectedId != currentQRId
                    let isRapidChange = currentQRDetectionTime.map { Date().timeIntervalSince($0) < qrChangeDetectionWindow } ?? false
                    
                    if isNewQR || isRapidChange {
                        currentQRId = detectedId
                        currentQRDetectionTime = Date()
                        
                        await MainActor.run {
                            navigationState.currentQRId = detectedId
                            navigationState.lastQRDetectionTime = Date()
                            navigationState.qrDetectionCount += 1
                        }
                        
                        print("NavigationManager: QR detected: '\(detectedId)' (new=\(isNewQR))")
                    }
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
    }
    
    // MARK: - Position Updates
    
    private func sendFirstPositionUpdate() async {
        guard let calibration = tempCalibrationData else { return }
        
        let request = UpdateRequest(
            currentX: calibration.mapStartX,
            currentY: calibration.mapStartY,
            currentBearing: calibration.initialBearing ?? 0.0,
            qrDetected: false,
            qrCodeId: nil
        )
        
        print("NavigationManager: First update at (\(calibration.mapStartX), \(calibration.mapStartY)), bearing: \(calibration.initialBearing ?? 0)")
        
        do {
            let response = try await NavigationAPIService.shared.updatePosition(request: request)
            print("NavigationManager: First response status: \(response.status)")
            print("NavigationManager: First response message: \(response.message ?? "nil")")
            print("NavigationManager: First response instructions: \(response.instructions ?? "nil")")
            await handleNavigationResponse(response, isFirstUpdate: true)
            
            // If the first response was just "on track" (filtered), give a helpful initial direction
            let firstMsg = (response.message ?? response.instructions ?? "").lowercased()
            if firstMsg.contains("on track") || firstMsg.contains("no value return") || firstMsg.isEmpty {
                let initialDirection = buildInitialDirectionInstruction()
                if !initialDirection.isEmpty {
                    let translated: String
                    if languageManager?.isFrench() == true {
                        translated = await languageManager?.translateFromEnglish(initialDirection) ?? initialDirection
                    } else {
                        translated = initialDirection
                    }
                    await MainActor.run {
                        navigationState.currentInstruction = translated
                    }
                    ttsManager?.speak(translated, force: true)
                    print("NavigationManager: 🔊 Initial direction: \(translated)")
                }
            }
        } catch {
            print("NavigationManager: First update error: \(error)")
        }
    }
    
    /// Build a helpful initial instruction based on path data
    private func buildInitialDirectionInstruction() -> String {
        let source = navigationState.source
        let destination = navigationState.destination
        
        guard !source.isEmpty, !destination.isEmpty else {
            return "Start walking to begin navigation."
        }
        
        return "Navigating from \(source) to \(destination). Start walking to receive turn-by-turn instructions."
    }
    
    private func startPositionUpdateLoop() {
        updateTask?.cancel()
        
        updateTask = Task {
            while !Task.isCancelled && navigationState.isNavigating {
                await performPositionUpdate()
                try? await Task.sleep(nanoseconds: updateIntervalMs * 1_000_000)
            }
        }
    }
    private func performPositionUpdate() async {
        guard let sensorManager = sensorManager else {
            print("NavigationManager: ⚠️ performPositionUpdate - sensorManager is nil")
            return
        }
        
        guard let mapPosition = sensorManager.getCurrentMapPosition() else {
            // This was failing silently - now we'll see it
            print("NavigationManager: ⚠️ performPositionUpdate - getCurrentMapPosition returned nil (calibrationManager not set?)")
            return
        }
        
        // Check for new steps (matching Android: only send on step change)
        let currentSteps = sensorManager.imuState.stepCount
        guard currentSteps > lastStepCount else { return }
        
        let stepsSinceLastUpdate = currentSteps - lastStepCount
        lastStepCount = currentSteps
        
        // Get smart QR state
        let (qrDetected, qrId) = getSmartQRState()
        
        // Track sent QR
        if qrDetected, let qrId = qrId {
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
        
        print("NavigationManager: 📍 Sending update #\(currentSteps) at (\(String(format: "%.2f", mapPosition.x)), \(String(format: "%.2f", mapPosition.y))), bearing: \(String(format: "%.1f", mapPosition.bearing))°")
        
        do {
            let response = try await NavigationAPIService.shared.updatePosition(request: request)
            retryCount = 0
            
            // Handle segment info BEFORE handling response (matching Android order)
            if let segmentInfo = response.segmentInfo {
                updateCurrentSegmentId(segmentInfo.segmentIndex)
            }
            
            // Handle segment-based recalibration (MATCHING ANDROID exactly)
            if response.status == "segment_change", let newPos = response.newMapPosition, newPos.count >= 2 {
                await handleSegmentRecalibration(response: response, reason: "segment_change")
            }
            
            if response.status == "segment_ending", let newPos = response.newMapPosition, newPos.count >= 2 {
                await handleSegmentRecalibration(response: response, reason: "segment_ending")
            }
            
            // Handle navigation instruction
            await handleNavigationResponse(response, isFirstUpdate: false)
            
        } catch {
            retryCount += 1
            print("NavigationManager: Update error (attempt \(retryCount)): \(error)")
            
            if retryCount >= maxRetryAttempts {
                await MainActor.run {
                    navigationState.errorMessage = "Connection lost after \(retryCount) attempts"
                }
                ttsManager?.speakCritical("Connection lost")
                retryCount = 0
                try? await Task.sleep(nanoseconds: retryDelayMs * 2 * 1_000_000)
            } else {
                try? await Task.sleep(nanoseconds: retryDelayMs * 1_000_000)
            }
        }
    }
    
    // MARK: - Response Handling (MATCHING ANDROID LOGIC)
    
    private func handleNavigationResponse(_ response: NavigationResponse, isFirstUpdate: Bool) async {
        // CRITICAL FIX: Match Android's instruction extraction order
        let newInstruction = response.message ?? response.instructions
        
        guard let instruction = newInstruction, !instruction.isEmpty else {
            if response.status == "error" {
                let errorMsg = "Server error: \(response.message ?? "Unknown")"
                print("NavigationManager: \(errorMsg)")
                await MainActor.run {
                    navigationState.errorMessage = errorMsg
                }
                ttsManager?.speakCritical("Navigation error occurred")
            }
            return
        }
        
        // Translate if needed
        let translatedInstruction: String
        if languageManager?.isFrench() == true {
            translatedInstruction = await languageManager?.translateFromEnglish(instruction) ?? instruction
        } else {
            translatedInstruction = instruction
        }
        
        // Update UI state ON MAIN THREAD
        await MainActor.run {
            navigationState.currentInstruction = translatedInstruction
            navigationState.serverResponse = response.message
            navigationState.lastUpdateTime = Date()
            navigationState.errorMessage = nil
        }
        
        // Handle instruction announcement (matching Android logic)
        handleInstructionAnnouncement(translatedInstruction, isFirst: isFirstUpdate)
        
        // Check for destination arrival AFTER TTS (matching Android)
        if instruction.contains("Arrived! Destination") || instruction.lowercased().contains("arrived") {
            print("NavigationManager: 🎉 Destination reached!")
            // Give TTS time to speak, then stop
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                stopNavigation()
            }
        }
    }
    
    // MARK: - Instruction Announcement (MATCHING ANDROID)
    
    private func handleInstructionAnnouncement(_ instruction: String, isFirst: Bool = false) {
        let lowerInstruction = instruction.lowercased().trimmingCharacters(in: .whitespaces)
        
        // MATCHING ANDROID skip phrases exactly
        let skipPhrases = [
            "no value return",
            "you are on track",
            "pas de valeur de retour",
            "aucune valeur de retour",
            "valeur de retour",
            "on track",
            "vous êtes sur la bonne voie",
            "sur la bonne voie",
            "press start",
            "update received",
            "position updated"
        ]
        
        if skipPhrases.contains(where: { lowerInstruction.contains($0) }) || instruction.trimmingCharacters(in: .whitespaces).isEmpty {
            print("NavigationManager: Filtered skip phrase: '\(instruction)'")
            return
        }
        
        // Don't repeat same instruction
        if instruction == lastInstructionText && !isFirst {
            return
        }
        
        lastInstructionText = instruction
        
        // Check timing
        let timeSinceLast = Date().timeIntervalSince(lastInstructionTime)
        guard isFirst || timeSinceLast >= minInstructionInterval else { return }
        
        lastInstructionTime = Date()
        
        print("NavigationManager: 🔊 Speaking: \"\(instruction)\"")
        
        // Use appropriate TTS priority (matching Android)
        if ttsManager?.isEmergencyCorrection(instruction) == true {
            ttsManager?.speakEmergencyCorrection(instruction)
        } else if isFirst {
            ttsManager?.speak(instruction, force: true)
        } else {
            ttsManager?.speak(instruction)
        }
    }
    
    // MARK: - Segment & Bearing Correction (MATCHING ANDROID)
    
    private func updateCurrentSegmentId(_ segmentId: Int) {
        if segmentId != currentSegmentId {
            currentSegmentId = segmentId
            // Update sensor manager so next step uses correct bearing
            sensorManager?.setBearingCorrectionData(pathBearings, segmentId)
            print("NavigationManager: Segment updated to \(segmentId)")
        }
    }
    
    private func handleSegmentRecalibration(response: NavigationResponse, reason: String) async {
        guard let newMapPosition = response.newMapPosition, newMapPosition.count >= 2 else {
            print("NavigationManager: Invalid new_map_position for \(reason)")
            return
        }
        
        let mapX = newMapPosition[0]
        let mapY = newMapPosition[1]
        
        // Determine bearing based on reason (matching Android logic)
        let mapBearing: Double?
        switch reason {
        case "segment_ending":
            // Preserve current bearing for segment endings
            mapBearing = sensorManager?.getCurrentMapPosition()?.bearing
        case "segment_change":
            // Use current bearing for segment changes too
            mapBearing = sensorManager?.getCurrentMapPosition()?.bearing
        default:
            mapBearing = sensorManager?.getCurrentMapPosition()?.bearing
        }
        
        print("NavigationManager: Recalibrating for \(reason) at (\(mapX), \(mapY))")
        
        // Reset IMU position
        sensorManager?.resetPosition()
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        guard let resetPosition = sensorManager?.getCurrentPosition() else {
            print("NavigationManager: Failed to get reset position for recalibration")
            return
        }
        
        let success = calibrationManager?.calibrateWithMapPosition(
            currentImuPosition: resetPosition,
            mapX: mapX,
            mapY: mapY,
            mapBearing: mapBearing,
            stepCount: sensorManager?.imuState.stepCount ?? 0
        ) ?? false
        
        if success {
            let calibrationType = reason == "segment_ending" ? "position only, bearing preserved" : "position + bearing"
            print("NavigationManager: ✓ \(reason) recalibration successful (\(calibrationType))")
            
            await MainActor.run {
                navigationState.currentInstruction = "\(response.message ?? "Recalibrated") (Position recalibrated - \(reason))"
                navigationState.lastUpdateTime = Date()
            }
        } else {
            print("NavigationManager: ✗ \(reason) recalibration failed")
            await MainActor.run {
                navigationState.errorMessage = "\(reason) recalibration failed, continuing with current calibration"
            }
        }
    }
    
    func getNavigationSummary() -> [String: Any] {
        let state = navigationState
        let currentPosition = sensorManager?.getCurrentPosition()
        let mapPosition = sensorManager?.getCurrentMapPosition()

        return [
            "isNavigating": state.isNavigating,
            "isInitialized": state.isInitialized,
            "instruction": state.currentInstruction,
            "route": "\(state.source) → \(state.destination)",
            "imuPosition": currentPosition.map {
                "(\(String(format: "%.2f", $0.x)), \(String(format: "%.2f", $0.y)))"
            } ?? "Unknown",
            "mapPosition": mapPosition.map {
                "(\(String(format: "%.2f", $0.x)), \(String(format: "%.2f", $0.y)))"
            } ?? "Not calibrated",
            "bearing": currentPosition.map {
                "\(String(format: "%.1f", $0.bearing))°"
            } ?? "Unknown",
            "lastUpdate": state.lastUpdateTime.timeIntervalSinceNow < -1 ?
                "\(Int(-state.lastUpdateTime.timeIntervalSinceNow))s ago" : "Just now",
            "qrDetectionActive": state.qrDetectionActive,
            "currentQRId": state.currentQRId ?? "None",
            "lastSentQRId": state.lastSentQRId ?? "None",
            "qrDetectionCount": state.qrDetectionCount,
            "qrEngine": "VISION",
            "qrSyncMode": state.qrSyncMode,
            "currentSegmentId": state.currentSegmentId,
            "smartQRInfo": getSmartQRInfo()
        ]
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        updateTask?.cancel()
        qrMonitoringTask?.cancel()
    }
    
    func testQRDetection() {
        print("NavigationManager: Testing QR detection")
        qrDetector?.testVisionCapabilities()
    }
    
    func getSmartQRInfo() -> [String: Any] {
        return [
            "mode": navigationState.qrSyncMode,
            "currentQRId": currentQRId ?? "none",
            "lastSentQRId": lastSentQRId ?? "none",
            "persistenceWindow": qrPersistenceWindow
        ]
    }
    
    func resumeQRDetection() {
        if navigationState.isNavigating {
            qrDetector?.startScanning()
        }
    }
}
