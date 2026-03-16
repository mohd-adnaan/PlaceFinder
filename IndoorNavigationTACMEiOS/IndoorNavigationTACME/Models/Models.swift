//
//  Models.swift
//  IndoorNavigationTACME
//
//  Data models for the indoor navigation system
//  FIXED: IMUState now includes calibrationStepCount
//

import Foundation

// MARK: - API Request/Response Models

/// Request to initialize navigation session
struct InitializeRequest: Codable {
    let action: String
    let source: String
    let destination: String
    let useClockDirections: Bool
    let useLandmarks: Bool
    let conversationMode: Bool
    
    init(source: String, destination: String, useClockDirections: Bool = false, useLandmarks: Bool = false, conversationMode: Bool = false) {
        self.action = "initialize"
        self.source = source
        self.destination = destination
        self.useClockDirections = useClockDirections
        self.useLandmarks = useLandmarks
        self.conversationMode = conversationMode
    }
    
    enum CodingKeys: String, CodingKey {
        case action, source, destination
        case useClockDirections
        case useLandmarks
        case conversationMode
    }
}

/// Request to update current position
struct UpdateRequest: Codable {
    let action: String
    let currentX: Double
    let currentY: Double
    let currentBearing: Double
    let qrDetected: Bool
    let qrCodeId: String?
    
    init(currentX: Double, currentY: Double, currentBearing: Double, qrDetected: Bool = false, qrCodeId: String? = nil) {
        self.action = "update"
        self.currentX = currentX
        self.currentY = currentY
        self.currentBearing = currentBearing
        self.qrDetected = qrDetected
        self.qrCodeId = qrCodeId
    }
}

/// Calibration data from server
struct CalibrationData: Codable {
    let mapStartX: Double
    let mapStartY: Double
    let initialBearing: Double?
}

/// Segment information
struct SegmentInfo: Codable {
    let segmentIndex: Int
    let isSignificantTurn: Bool?
}

/// Navigation response from server
struct NavigationResponse: Codable {
    let status: String
    let message: String?
    let instructions: String?
    let navigationStarted: Bool?
    let pathCoordinates: [[Double]]?
    let pathBearings: [Double]?
    let calibration: CalibrationData?
    let waypoint: [Double]?
    let distancePassed: Double?
    let returnTurn: String?
    let returnAngle: Double?
    let correctTurn: String?
    let correctAngle: Double?
    let deviationType: String?
    let correctionPoint: [Double]?
    let newMapPosition: [Double]?
    let conversationMode: Bool?
    let conversationData: AnyCodable?
    let segmentInfo: SegmentInfo?
}

/// Type-erased Codable wrapper
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        } else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else {
            try container.encodeNil()
        }
    }
}

// MARK: - Position Model

/// 2D position with bearing
struct Position: Equatable {
    var x: Double
    var y: Double
    var bearing: Double
    
    init(x: Double = 0, y: Double = 0, bearing: Double = 0) {
        self.x = x
        self.y = y
        self.bearing = bearing
    }
}

// MARK: - IMU State

/// State of IMU sensors and step detection
/// FIXED: Now includes calibrationStepCount for real-time calibration feedback
struct IMUState {
    var position: Position
    var stepCount: Int
    var isCalibrated: Bool
    var accelerationMagnitude: Float
    var isMoving: Bool
    var currentStepLength: Double
    var filterQuality: String
    var beta: Double
    var isStepCalibrationValid: Bool
    var isCalibrating: Bool
    var calibrationStepCount: Int = 0
    var bearing: Double
    
    init(
        position: Position = Position(),
        stepCount: Int = 0,
        isCalibrated: Bool = false,
        accelerationMagnitude: Float = 0,
        isMoving: Bool = false,
        currentStepLength: Double = 0.65,
        filterQuality: String = "Initializing",
        beta: Double = 0.6,
        isStepCalibrationValid: Bool = false,
        isCalibrating: Bool = false,
        calibrationStepCount: Int = 0,
        bearing: Double = 0
    ) {
        self.position = position
        self.stepCount = stepCount
        self.isCalibrated = isCalibrated
        self.accelerationMagnitude = accelerationMagnitude
        self.isMoving = isMoving
        self.currentStepLength = currentStepLength
        self.filterQuality = filterQuality
        self.beta = beta
        self.isStepCalibrationValid = isStepCalibrationValid
        self.isCalibrating = isCalibrating
        self.calibrationStepCount = calibrationStepCount
        self.bearing = bearing
    }
}

// MARK: - Acceleration Sample

/// Extended to match Android's AccelerationSample for research export parity.
/// Fields isPeak, isValley, isConfirmedStep, stepLength, stepNumber, peakValleyDiff
/// are set retroactively by the AccelerationLogger mark methods.
struct AccelerationSample {
    let sampleIndex: Int
    let timestamp: Date
    let x: Double
    let y: Double
    let z: Double
    let magnitude: Double
    let filtered: Double
    // Step-detection metadata (set retroactively by logger mark methods)
    var isPeak: Bool = false
    var isValley: Bool = false
    var isConfirmedStep: Bool = false
    var stepLength: Double? = nil
    var stepNumber: Int? = nil
    var peakValleyDiff: Double? = nil
}

// MARK: - Bearing Result

struct BearingResult {
    let bearing: Double
    let wasCorrected: Bool
    
    init(_ bearing: Double, _ wasCorrected: Bool) {
        self.bearing = bearing
        self.wasCorrected = wasCorrected
    }
}

// MARK: - Navigation State

/// State of the navigation system
struct NavigationState {
    var isNavigating: Bool
    var isInitialized: Bool
    var isCalibrated: Bool
    var currentInstruction: String
    var serverResponse: String?
    var source: String
    var destination: String
    var useClockDirections: Bool
    var useLandmarks: Bool
    var lastUpdateTime: Date
    var errorMessage: String?
    var initializationStep: InitStep
    // QR state
    var qrDetectionActive: Bool
    var lastQRDetectionTime: Date?
    var qrDetectionCount: Int
    var currentQRId: String?
    var lastSentQRId: String?
    var qrSyncMode: String
    // Bearing correction state
    var currentSegmentId: Int
    var trueBearing: Double?
    var bearingCorrectionApplied: Bool
    var bearingCorrectionCount: Int
    
    init(
        isNavigating: Bool = false,
        isInitialized: Bool = false,
        isCalibrated: Bool = false,
        currentInstruction: String = "Ready to navigate",
        serverResponse: String? = nil,
        source: String = "",
        destination: String = "",
        useClockDirections: Bool = false,
        useLandmarks: Bool = false,
        lastUpdateTime: Date = Date(),
        errorMessage: String? = nil,
        initializationStep: InitStep = .notStarted,
        qrDetectionActive: Bool = false,
        lastQRDetectionTime: Date? = nil,
        qrDetectionCount: Int = 0,
        currentQRId: String? = nil,
        lastSentQRId: String? = nil,
        qrSyncMode: String = "SMART_SYNC",
        currentSegmentId: Int = -1,
        trueBearing: Double? = nil,
        bearingCorrectionApplied: Bool = false,
        bearingCorrectionCount: Int = 0
    ) {
        self.isNavigating = isNavigating
        self.isInitialized = isInitialized
        self.isCalibrated = isCalibrated
        self.currentInstruction = currentInstruction
        self.serverResponse = serverResponse
        self.source = source
        self.destination = destination
        self.useClockDirections = useClockDirections
        self.useLandmarks = useLandmarks
        self.lastUpdateTime = lastUpdateTime
        self.errorMessage = errorMessage
        self.initializationStep = initializationStep
        self.qrDetectionActive = qrDetectionActive
        self.lastQRDetectionTime = lastQRDetectionTime
        self.qrDetectionCount = qrDetectionCount
        self.currentQRId = currentQRId
        self.lastSentQRId = lastSentQRId
        self.qrSyncMode = qrSyncMode
        self.currentSegmentId = currentSegmentId
        self.trueBearing = trueBearing
        self.bearingCorrectionApplied = bearingCorrectionApplied
        self.bearingCorrectionCount = bearingCorrectionCount
    }
}

/// Navigation initialization steps
enum InitStep: String, CaseIterable {
    case notStarted = "NOT_STARTED"
    case connecting = "CONNECTING"
    case serverResponse = "SERVER_RESPONSE"
    case calibrating = "CALIBRATING"
    case completed = "COMPLETED"
    case initialized = "INITIALIZED"
    case navigating = "NAVIGATING"
    case error = "ERROR"
}

// MARK: - TTS State

/// State of text-to-speech system
struct TTSState {
    var isReady: Bool
    var isEnabled: Bool
    var isSpeaking: Bool
    var lastSpokenText: String
    var lastSpeechTime: Date?
    
    init(
        isReady: Bool = false,
        isEnabled: Bool = true,
        isSpeaking: Bool = false,
        lastSpokenText: String = "",
        lastSpeechTime: Date? = nil
    ) {
        self.isReady = isReady
        self.isEnabled = isEnabled
        self.isSpeaking = isSpeaking
        self.lastSpokenText = lastSpokenText
        self.lastSpeechTime = lastSpeechTime
    }
}

// MARK: - QR Detection State

/// QR scan mode
enum QRScanMode {
    case normal
    case walking
}

/// State of QR code detection
struct QRDetectionState {
    var isDetected: Bool
    var lastDetectionTime: Date?
    var detectionCount: Int
    var isScanning: Bool
    var lastQRContent: String?
    var detectedContent: String?
    var actualResolution: String
    var avgProcessingTime: Float
    var frameRate: Float
    var walkingOptimized: Bool
    var detectionEngine: String
    var rapidChangeMode: Bool
    var changeDetectionEnabled: Bool
    var scanMode: QRScanMode
    
    init(
        isDetected: Bool = false,
        lastDetectionTime: Date? = nil,
        detectionCount: Int = 0,
        isScanning: Bool = false,
        lastQRContent: String? = nil,
        detectedContent: String? = nil,
        actualResolution: String = "",
        avgProcessingTime: Float = 0,
        frameRate: Float = 0,
        walkingOptimized: Bool = true,
        detectionEngine: String = "VISION",
        rapidChangeMode: Bool = false,
        changeDetectionEnabled: Bool = true,
        scanMode: QRScanMode = .walking
    ) {
        self.isDetected = isDetected
        self.lastDetectionTime = lastDetectionTime
        self.detectionCount = detectionCount
        self.isScanning = isScanning
        self.lastQRContent = lastQRContent
        self.detectedContent = detectedContent
        self.actualResolution = actualResolution
        self.avgProcessingTime = avgProcessingTime
        self.frameRate = frameRate
        self.walkingOptimized = walkingOptimized
        self.detectionEngine = detectionEngine
        self.rapidChangeMode = rapidChangeMode
        self.changeDetectionEnabled = changeDetectionEnabled
        self.scanMode = scanMode
    }
}

// MARK: - Conversation State

/// Chat message
struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    
    init(content: String, isUser: Bool) {
        self.content = content
        self.isUser = isUser
    }
}

/// Location intent extracted from user input
struct LocationIntent {
    var isNewRouteRequest: Bool
    var isQuestionAboutRoute: Bool
    var needsClarification: Bool
    var source: String?
    var destination: String?
    var clarificationMessage: String?
    
    init(
        isNewRouteRequest: Bool = false,
        isQuestionAboutRoute: Bool = false,
        needsClarification: Bool = false,
        source: String? = nil,
        destination: String? = nil,
        clarificationMessage: String? = nil
    ) {
        self.isNewRouteRequest = isNewRouteRequest
        self.isQuestionAboutRoute = isQuestionAboutRoute
        self.needsClarification = needsClarification
        self.source = source
        self.destination = destination
        self.clarificationMessage = clarificationMessage
    }
}

/// State of AI conversation
struct ConversationState {
    var isActive: Bool
    var isListening: Bool
    var currentMessage: String
    var currentSpeechText: String
    var gptResponse: String
    var hasRouteData: Bool
    var isProcessing: Bool
    var errorMessage: String?
    var lastError: String?
    var messages: [ChatMessage]
    var extractedIntent: LocationIntent?
    
    init(
        isActive: Bool = false,
        isListening: Bool = false,
        currentMessage: String = "",
        currentSpeechText: String = "",
        gptResponse: String = "",
        hasRouteData: Bool = false,
        isProcessing: Bool = false,
        errorMessage: String? = nil,
        lastError: String? = nil,
        messages: [ChatMessage] = [],
        extractedIntent: LocationIntent? = nil
    ) {
        self.isActive = isActive
        self.isListening = isListening
        self.currentMessage = currentMessage
        self.currentSpeechText = currentSpeechText
        self.gptResponse = gptResponse
        self.hasRouteData = hasRouteData
        self.isProcessing = isProcessing
        self.errorMessage = errorMessage
        self.lastError = lastError
        self.messages = messages
        self.extractedIntent = extractedIntent
    }
}

// MARK: - Language

/// Supported languages
enum Language: String, CaseIterable {
    case english = "en"
    case french = "fr"
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .french: return "Français"
        }
    }
    
    var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en-US")
        case .french: return Locale(identifier: "fr-CA")
        }
    }
}
