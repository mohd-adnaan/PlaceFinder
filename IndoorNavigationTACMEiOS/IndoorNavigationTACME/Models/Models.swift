//
//  Models.swift
//  IndoorNavigationTACME
//
//  Data models for the indoor navigation system
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
    
    enum CodingKeys: String, CodingKey {
        case status, message, instructions, navigationStarted, pathCoordinates
        case pathBearings, calibration, waypoint
        case distancePassed = "distance_passed"
        case returnTurn = "return_turn"
        case returnAngle = "return_angle"
        case correctTurn = "correct_turn"
        case correctAngle = "correct_angle"
        case deviationType = "deviation_type"
        case correctionPoint = "correction_point"
        case newMapPosition = "new_map_position"
        case conversationMode = "conversation_mode"
        case conversationData = "conversation_data"
        case segmentInfo
    }
}

// MARK: - Position Models

/// Represents a position in coordinate space
struct Position: Equatable {
    var x: Double
    var y: Double
    var bearing: Double
    var timestamp: Date
    
    init(x: Double = 0, y: Double = 0, bearing: Double = 0, timestamp: Date = Date()) {
        self.x = x
        self.y = y
        self.bearing = bearing
        self.timestamp = timestamp
    }
    
    static func == (lhs: Position, rhs: Position) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.bearing == rhs.bearing
    }
}

// MARK: - IMU State

/// State of the IMU sensor system
struct IMUState {
    var position: Position
    var stepCount: Int
    var isCalibrated: Bool
    var accelerationMagnitude: Float
    var isMoving: Bool
    var currentStepLength: Double
    var filterQuality: String
    var beta: Double  // Step length beta factor (Weinberg method)
    var isStepCalibrationValid: Bool
    var isCalibrating: Bool
    var calibrationStepCount: Int
    var bearing: Double
    
    init(
        position: Position = Position(),
        stepCount: Int = 0,
        isCalibrated: Bool = false,
        accelerationMagnitude: Float = 0,
        isMoving: Bool = false,
        currentStepLength: Double = 0,
        filterQuality: String = "Initializing",
        beta: Double = 0.415,
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

// MARK: - Navigation State

/// Current state of navigation
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
    var detectedContent: String?  // Current detected QR content
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

/// State of AI conversation
struct ConversationState {
    var isActive: Bool
    var isListening: Bool
    var currentMessage: String
    var currentSpeechText: String  // Current speech being recognized
    var gptResponse: String
    var hasRouteData: Bool
    var isProcessing: Bool
    var errorMessage: String?
    var lastError: String?
    var messages: [ChatMessage]  // Chat history
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

/// A single chat message
struct ChatMessage: Identifiable {
    let id: UUID
    let content: String  // Message content
    let isUser: Bool
    let timestamp: Date
    
    init(id: UUID = UUID(), content: String, isUser: Bool, timestamp: Date = Date()) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
    }
}

/// Location intent parsed from user input
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

// MARK: - Calibration State

/// State of IMU calibration
struct CalibrationState {
    var isPositionCalibrated: Bool
    var isBearingCalibrated: Bool
    var positionOffsetX: Double
    var positionOffsetY: Double
    var bearingOffset: Double
    var calibrationConfidence: Double
    var calibrationTimestamp: Date?
    var permanentBearingOffset: Double?
    var initialBearing: Double?
    
    init(
        isPositionCalibrated: Bool = false,
        isBearingCalibrated: Bool = false,
        positionOffsetX: Double = 0,
        positionOffsetY: Double = 0,
        bearingOffset: Double = 0,
        calibrationConfidence: Double = 0,
        calibrationTimestamp: Date? = nil,
        permanentBearingOffset: Double? = nil,
        initialBearing: Double? = nil
    ) {
        self.isPositionCalibrated = isPositionCalibrated
        self.isBearingCalibrated = isBearingCalibrated
        self.positionOffsetX = positionOffsetX
        self.positionOffsetY = positionOffsetY
        self.bearingOffset = bearingOffset
        self.calibrationConfidence = calibrationConfidence
        self.calibrationTimestamp = calibrationTimestamp
        self.permanentBearingOffset = permanentBearingOffset
        self.initialBearing = initialBearing
    }
}

// MARK: - Helper Types

/// Type-erased Codable wrapper for handling Any types in JSON
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - Acceleration Sample (for debugging/analysis)

struct AccelerationSample {
    let timestamp: Date
    let x: Double
    let y: Double
    let z: Double
    let magnitude: Double
    let filtered: Double
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
