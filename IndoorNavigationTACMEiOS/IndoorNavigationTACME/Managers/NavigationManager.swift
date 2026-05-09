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
    private var didUploadSession: Bool = false
    
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
        
        let isFrenchAlignment = languageManager?.isFrench() == true
        let sourceName = navigationState.source.isEmpty ? "your starting point" : navigationState.source
        let spokenSource = sourceName
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([A-Za-z])([0-9])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
        let alignmentMessage = isFrenchAlignment
            ? "Veuillez vous positionner dos à \(spokenSource) avant de commencer la navigation."
            : "Please position yourself with your back facing \(spokenSource) before we begin."
        ttsManager?.speak(alignmentMessage, force: true)
        
        print("NavigationManager: Waiting for user to align (back facing \(sourceName))...")
        try? await Task.sleep(nanoseconds: 5_500_000_000)
        
        // Reset sensors before calibration
        sensorManager?.resetPosition()
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        guard let currentImuPosition = sensorManager?.getCurrentPosition() else {
            return .failure(NSError(domain: "Nav", code: -3, userInfo: [NSLocalizedDescriptionKey: "Sensor error"]))
        }
        
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
        
        lastStepCount = sensorManager?.imuState.stepCount ?? 0
        lastInstructionText = ""
        lastInstructionTime = Date.distantPast
        updateCount = 0
        retryCount = 0
        didUploadSession = false
        
        await MainActor.run {
            navigationState.isCalibrated = true
            navigationState.isNavigating = true
            navigationState.initializationStep = .navigating
            navigationState.currentInstruction = "Starting navigation..."
            navigationState.qrDetectionActive = true
            navigationState.qrSyncMode = "SMART_SYNC"
        }
        
        await MainActor.run {
            qrDetector?.startScanning()
        }
        
        let message = languageManager?.isFrench() == true
            ? (await languageManager?.translateFromEnglish("Navigation started") ?? "Navigation started")
            : "Navigation started"
        ttsManager?.speak(message, force: true)
        
        print("NavigationManager: Sending FIRST position update at calibration point...")
        await sendFirstPositionUpdate()
        
        startPositionUpdateLoop()
        startQRMonitoring()
        
        return .success(())
    }
    
    func stopNavigation() {
        print("NavigationManager: Stopping navigation")
        
        updateTask?.cancel()
        updateTask = nil
        qrMonitoringTask?.cancel()
        qrMonitoringTask = nil
        
        qrDetector?.stopScanning()
        
        currentQRId = nil
        currentQRDetectionTime = nil
        lastSentQRId = nil
        
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

        triggerAutoUpload(reason: "stop_navigation")
        
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
            // Handle recalibration for force-update path
            await handleRecalibrationFromResponse(response)
            await handleNavigationResponse(response)
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
        
        if elapsed <= qrPersistenceWindow {
            if qrId == lastSentQRId && elapsed > qrChangeDetectionWindow {
                return (false, nil)
            }
            return (true, qrId)
        }
        
        currentQRId = nil
        currentQRDetectionTime = nil
        return (false, nil)
    }
    
    private func startQRMonitoring() {
        qrMonitoringTask?.cancel()
        qrMonitoringTask = Task {
            while !Task.isCancelled && navigationState.isNavigating {
                if let qrDetector = qrDetector,
                   qrDetector.detectionState.isDetected,
                   let rawContent = qrDetector.detectionState.detectedContent {
                    
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
                
                try? await Task.sleep(nanoseconds: 100_000_000)
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
            
            // Handle recalibration for first-update path
            await handleRecalibrationFromResponse(response)
            await handleNavigationResponse(response)
            
            // If first response was just "on track", give helpful initial direction
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
            
            // Handle segment info BEFORE recalibration (matching Android order)
            if let segmentInfo = response.segmentInfo {
                updateCurrentSegmentId(segmentInfo.segmentIndex)
            }
            
            // ── CRITICAL: Gate recalibration by status (matching Android exactly) ──
            // Android only recalibrates for segment_change and segment_ending.
            // no_segment_ending: bearing-only update, NO position recalibration.
            let status = response.status.lowercased()
            
            if status == "segment_change", let newPos = response.newMapPosition, newPos.count >= 2 {
                await handleSegmentRecalibration(response: response, reason: "segment_change")
            }
            
            if status == "segment_ending", let newPos = response.newMapPosition, newPos.count >= 2 {
                await handleSegmentRecalibration(response: response, reason: "segment_ending")
            }
            
            // no_segment_ending: bearing-only correction, NO position snap
            if status == "no_segment_ending", let newPos = response.newMapPosition, newPos.count >= 3 {
                let bearing = newPos[2]
                sensorManager.setInitialBearing(bearing)
                print("NavigationManager: no_segment_ending — bearing-only update to \(String(format: "%.1f", bearing))°, NO position recalibration")
            }
            
            // Handle navigation message/TTS (no recalibration — already done above)
            await handleNavigationResponse(response)
            
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
    
    // MARK: - Recalibration from non-loop paths (forceUpdate, firstUpdate)
    
    /// Handles recalibration for code paths that don't go through performPositionUpdate
    /// (sendFirstPositionUpdate, forcePositionUpdate). performPositionUpdate handles
    /// recalibration inline before calling handleNavigationResponse.
    private func handleRecalibrationFromResponse(_ response: NavigationResponse) async {
        let status = response.status.lowercased()
        
        if let segmentInfo = response.segmentInfo {
            updateCurrentSegmentId(segmentInfo.segmentIndex)
        }
        
        guard let newPos = response.newMapPosition, newPos.count >= 2 else { return }
        
        switch status {
        case "segment_change":
            await handleSegmentRecalibration(response: response, reason: "segment_change")
        case "segment_ending":
            await handleSegmentRecalibration(response: response, reason: "segment_ending")
        case "no_segment_ending":
            if newPos.count >= 3 {
                sensorManager?.setInitialBearing(newPos[2])
                print("NavigationManager: no_segment_ending — bearing-only update to \(String(format: "%.1f", newPos[2]))°")
            }
        default:
            break
        }
    }
    
    // MARK: - Response Handling (message + TTS only, NO recalibration)
    
    private func handleNavigationResponse(_ response: NavigationResponse) async {
        let status = response.status.lowercased()
        
        // Use message field (Android: response.message ?: response.instructions)
        // Backend sends turn instructions in "message" with instructions=null
        let instructionText = response.message ?? response.instructions
        
        guard let instruction = instructionText, !instruction.isEmpty else { return }
        
        let translatedInstruction: String
        if languageManager?.isFrench() == true {
            translatedInstruction = await languageManager?.translateFromEnglish(instruction) ?? instruction
        } else {
            translatedInstruction = instruction
        }
        
        // Filter skip phrases (matching Android)
        let lowerInstruction = translatedInstruction.lowercased()
        let skipPhrases = [
            "no value return",
            "you are on track",
            "on track",
            "pas de valeur de retour",
            "aucune valeur de retour",
            "valeur de retour",
            "vous êtes sur la bonne voie",
            "sur la bonne voie"
        ]
        
        if skipPhrases.contains(where: { lowerInstruction.contains($0) }) {
            print("NavigationManager: Filtered skip phrase: '\(instruction)'")
            return
        }
        
        await MainActor.run {
            navigationState.currentInstruction = translatedInstruction
            navigationState.serverResponse = response.message
            navigationState.lastUpdateTime = Date()
        }
        
        // Announce with status-aware priority routing
        handleInstructionAnnouncement(translatedInstruction, status: status)
        print("NavigationManager: 🔊 Speaking: \"\(translatedInstruction)\"")
        
        // Handle destination reached
        if status == "destination_reached" {
            print("NavigationManager: 🎉 Destination reached!")
            triggerAutoUpload(reason: "destination_reached")
            await MainActor.run {
                navigationState.isNavigating = false
            }
        }
    }

    // MARK: - Auto Upload

    private func triggerAutoUpload(reason: String) {
        guard !didUploadSession else { return }
        guard let sensorManager = sensorManager else { return }

        didUploadSession = true
        DebugLogger.shared.log(.export, .info, "Auto upload: \(reason)")

        Task {
            _ = await DataExportManager.shared.uploadFullResearchBundle(
                sensorManager: sensorManager,
                navigationManager: self
            )
        }
    }
    
    // MARK: - Instruction Announcement (MATCHING ANDROID)
    
    private func handleInstructionAnnouncement(_ instruction: String, status: String = "") {
        let lowerInstruction = instruction.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Skip filler phrases
        let skipPhrases = [
            "continue moving",
            "keep going",
            "you're on track",
            "on the right path"
        ]
        
        if skipPhrases.contains(where: { lowerInstruction.contains($0) }) {
            return
        }
        
        // Emergency corrections: highest priority
        if ttsManager?.isEmergencyCorrection(instruction) == true {
            ttsManager?.speakEmergencyCorrection(instruction)
            return
        }
        
        // Determine if this needs priority treatment
        let isTurnInstruction = lowerInstruction.contains("turn") &&
            (lowerInstruction.contains("o'clock") ||
             lowerInstruction.contains("left") ||
             lowerInstruction.contains("right"))
        
        let isDestination = lowerInstruction.contains("arrived") ||
            lowerInstruction.contains("destination")
        
        let isSegmentTransition = (status == "segment_change" ||
                                    status == "no_segment_ending" ||
                                    status == "destination_reached")
        
        if isTurnInstruction || isDestination || isSegmentTransition {
            ttsManager?.speakPriority(instruction)
        } else {
            ttsManager?.speak(instruction)
        }
    }
    
    // MARK: - Segment & Bearing Correction (MATCHING ANDROID)
    
    private func updateCurrentSegmentId(_ segmentId: Int) {
        if segmentId != currentSegmentId {
            currentSegmentId = segmentId
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
        
        let mapBearing: Double?
        switch reason {
        case "segment_ending":
            mapBearing = sensorManager?.getCurrentMapPosition()?.bearing
        case "segment_change":
            mapBearing = sensorManager?.getCurrentMapPosition()?.bearing
        default:
            mapBearing = sensorManager?.getCurrentMapPosition()?.bearing
        }
        
        print("NavigationManager: Recalibrating for \(reason) at (\(mapX), \(mapY))")
        
        // resetPositionOnly preserves filter state — no phantom steps after recalibration
        sensorManager?.resetPositionOnly()
        lastStepCount = 0
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
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
        } else {
            print("NavigationManager: ✗ \(reason) recalibration failed")
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
