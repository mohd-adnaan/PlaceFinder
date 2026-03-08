//
//  Voicenavigationmanager.swift
//  IndoorNavigationTACME
//
//  Created by Mohammad Adnaan on 2026-03-07.
//
//
//  Voice-controlled navigation input manager.
//  Allows users to set source and destination via speech,
//  with confirmation flow and fuzzy POI matching.
//  iOS port of Android's VoiceInputManager.
//

import Foundation
import Speech
import AVFoundation
import Combine
import UIKit

class VoiceNavigationManager: ObservableObject {

    // MARK: - Types

    enum InputMode: Equatable {
        case none
        case listeningSource
        case confirmingSource
        case listeningDestination
        case confirmingDestination
        case confirmingBoth
    }

    struct VoiceInputState {
        var isListening: Bool = false
        var isReady: Bool = false
        var lastResult: String = ""
        var source: String = ""
        var destination: String = ""
        var isComplete: Bool = false
        var currentMode: InputMode = .none
        var errorMessage: String = ""
        var debugInfo: String = ""
        var waitingForConfirmation: Bool = false
        var confirmationPrompt: String = ""
        var retryCount: Int = 0
        var maxRetries: Int = 5
        var isInstructing: Bool = false
    }

    // MARK: - Published State

    @Published var voiceInputState = VoiceInputState()

    // MARK: - Private Properties

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var ttsManager: TTSManager?
    private var languageManager: LanguageManager?

    private var tempSource: String = ""
    private var tempDestination: String = ""
    private var availablePOIs: [String] = []
    private var feedbackGenerator: UIImpactFeedbackGenerator?

    // Timing constants (seconds)
    private let instructionDelay: TimeInterval = 3.5
    private let confirmationDelay: TimeInterval = 2.5
    private let retryDelay: TimeInterval = 2.5

    // MARK: - Initialization

    init() {
        feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        print("VoiceNavigationManager: Initialized")
    }

    // MARK: - Configuration

    func configure(ttsManager: TTSManager, languageManager: LanguageManager) {
        self.ttsManager = ttsManager
        self.languageManager = languageManager
        setupSpeechRecognizer()
        print("VoiceNavigationManager: Dependencies configured")
    }

    // MARK: - Public Methods

    /// Start the voice input flow for source + destination
    func startVoiceInput(poiNames: [String]) {
        availablePOIs = poiNames
        tempSource = ""
        tempDestination = ""

        voiceInputState = VoiceInputState()
        voiceInputState.isReady = true
        voiceInputState.currentMode = .listeningSource
        voiceInputState.isInstructing = true
        voiceInputState.debugInfo = "Starting voice navigation setup"

        let isFrench = languageManager?.currentLanguage == .french
        let prompt = isFrench
            ? "Quel est votre lieu de départ?"
            : "What is your starting location?"

        speakThenListen(prompt, delay: instructionDelay)
    }

    /// Cancel the voice input flow
    func cancelVoiceInput() {
        stopListening()
        tempSource = ""
        tempDestination = ""
        voiceInputState = VoiceInputState()

        let isFrench = languageManager?.currentLanguage == .french
        let message = isFrench
            ? "Navigation vocale annulée"
            : "Voice navigation cancelled"
        ttsManager?.speakPriority(message)

        print("VoiceNavigationManager: Voice input cancelled")
    }

    // MARK: - Speech Recognition

    private func setupSpeechRecognizer() {
        let locale = languageManager?.getCurrentLocale() ?? Locale(identifier: "en-US")
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        print("VoiceNavigationManager: Speech recognizer configured for \(locale.identifier)")
    }

    private func startListening() {
        guard voiceInputState.currentMode != .none else { return }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.performStartListening()
                case .denied, .restricted, .notDetermined:
                    self?.voiceInputState.errorMessage = "Speech recognition not authorized"
                    self?.voiceInputState.debugInfo = "Permission denied"
                @unknown default:
                    break
                }
            }
        }
    }

    private func performStartListening() {
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement,
                                         options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("VoiceNavigationManager: Audio session error: \(error)")
            voiceInputState.errorMessage = "Audio setup failed"
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let request = recognitionRequest,
              let recognizer = speechRecognizer else {
            voiceInputState.errorMessage = "Speech recognizer unavailable"
            return
        }

        request.shouldReportPartialResults = true

        if #available(iOS 13, *) {
            request.requiresOnDeviceRecognition = false
        }

        voiceInputState.isListening = true
        voiceInputState.debugInfo = "Listening..."

        feedbackGenerator?.impactOccurred()

        recognitionTask = recognizer.recognitionTask(with: request) {
            [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal

                DispatchQueue.main.async {
                    self.voiceInputState.lastResult = text
                    self.voiceInputState.debugInfo = "Heard: \(text)"
                }

                if isFinal {
                    DispatchQueue.main.async {
                        self.stopListening()
                        self.processRecognitionResult(text)
                    }
                }
            }

            if let error = error {
                DispatchQueue.main.async {
                    self.stopListening()
                    let nsError = error as NSError
                    // Code 203 = no speech, Code 1110 = no match
                    if nsError.code == 203 || nsError.code == 1110 {
                        self.handleNoSpeech()
                    } else {
                        self.voiceInputState.errorMessage = "Recognition error"
                        self.voiceInputState.debugInfo = "Error — retrying"
                        self.handleSpeechError()
                    }
                }
            }
        }

        // Install audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("VoiceNavigationManager: Audio engine start error: \(error)")
            voiceInputState.errorMessage = "Microphone error"
        }
    }

    private func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        voiceInputState.isListening = false
    }

    // MARK: - Result Processing

    private func processRecognitionResult(_ text: String) {
        let currentMode = voiceInputState.currentMode

        switch currentMode {
        case .listeningSource:
            let extracted = extractLocation(text, expectedType: "source")
            if !extracted.isEmpty {
                tempSource = extracted
                let isFrench = languageManager?.currentLanguage == .french
                let confirmMessage = isFrench
                    ? "Votre point de départ est \(extracted)?"
                    : "Is your starting location \(extracted)?"

                voiceInputState.currentMode = .confirmingSource
                voiceInputState.waitingForConfirmation = true
                voiceInputState.confirmationPrompt = confirmMessage
                voiceInputState.isInstructing = true
                voiceInputState.debugInfo = "Confirming source: \(extracted)"

                speakThenListen(confirmMessage, delay: confirmationDelay)
            } else {
                handleExtractionFailure("source", text, .listeningSource)
            }

        case .listeningDestination:
            let extracted = extractLocation(text, expectedType: "destination")
            if !extracted.isEmpty {
                tempDestination = extracted
                let isFrench = languageManager?.currentLanguage == .french
                let confirmMessage = isFrench
                    ? "Votre destination est \(extracted)?"
                    : "Is your destination \(extracted)?"

                voiceInputState.currentMode = .confirmingDestination
                voiceInputState.waitingForConfirmation = true
                voiceInputState.confirmationPrompt = confirmMessage
                voiceInputState.isInstructing = true
                voiceInputState.debugInfo = "Confirming destination: \(extracted)"

                speakThenListen(confirmMessage, delay: confirmationDelay)
            } else {
                handleExtractionFailure("destination", text, .listeningDestination)
            }

        case .confirmingSource:
            if isPositiveResponse(text) {
                let isFrench = languageManager?.currentLanguage == .french
                let prompt = isFrench
                    ? "Maintenant, quelle est votre destination?"
                    : "Now tell me your destination."

                voiceInputState.source = tempSource
                voiceInputState.currentMode = .listeningDestination
                voiceInputState.waitingForConfirmation = false
                voiceInputState.isInstructing = true
                voiceInputState.debugInfo = "Source confirmed, listening for destination"

                speakThenListen(prompt, delay: instructionDelay)
            } else if isNegativeResponse(text) {
                retryInput("source", mode: .listeningSource,
                           prompt: "Again. What is your starting location?")
            } else {
                let clarify = "Please say yes if \(tempSource) is correct, or no to try again."
                voiceInputState.isInstructing = true
                speakThenListen(clarify, delay: confirmationDelay)
            }

        case .confirmingDestination:
            if isPositiveResponse(text) {
                showFinalConfirmation()
            } else if isNegativeResponse(text) {
                retryInput("destination", mode: .listeningDestination,
                           prompt: "Again. Where do you want to go?")
            } else {
                let clarify = "Please say yes if \(tempDestination) is correct, or no to try again."
                voiceInputState.isInstructing = true
                speakThenListen(clarify, delay: confirmationDelay)
            }

        case .confirmingBoth:
            if isPositiveResponse(text) {
                completeVoiceInput()
            } else if isNegativeResponse(text) {
                restartVoiceInput()
            } else {
                let clarify = "Please say yes to confirm both locations, or no to start over."
                voiceInputState.isInstructing = true
                speakThenListen(clarify, delay: confirmationDelay)
            }

        case .none:
            break
        }
    }

    // MARK: - Confirmation Flow

    private func showFinalConfirmation() {
        let isFrench = languageManager?.currentLanguage == .french
        let finalMessage = isFrench
            ? "Parfait! Route de \(tempSource) à \(tempDestination)."
            : "Perfect! Route from \(tempSource) to \(tempDestination)."

        voiceInputState.currentMode = .confirmingBoth
        voiceInputState.confirmationPrompt = finalMessage
        voiceInputState.destination = tempDestination
        voiceInputState.isInstructing = true
        voiceInputState.debugInfo = "Final confirmation needed"

        speakThenListen(finalMessage, delay: instructionDelay)
    }

    private func completeVoiceInput() {
        print("VoiceNavigationManager: Completed — \(tempSource) → \(tempDestination)")

        voiceInputState.source = tempSource
        voiceInputState.destination = tempDestination
        voiceInputState.isComplete = true
        voiceInputState.currentMode = .none
        voiceInputState.waitingForConfirmation = false
        voiceInputState.isInstructing = false
        voiceInputState.debugInfo = "Voice input complete!"

        let isFrench = languageManager?.currentLanguage == .french
        let successMessage = isFrench
            ? "Excellent! Navigation de \(tempSource) à \(tempDestination). Pointez votre caméra vers un code QR."
            : "Excellent! Navigation from \(tempSource) to \(tempDestination). Point your camera at any QR code."

        ttsManager?.speakPriority(successMessage)
    }

    private func restartVoiceInput() {
        tempSource = ""
        tempDestination = ""

        voiceInputState.currentMode = .listeningSource
        voiceInputState.waitingForConfirmation = false
        voiceInputState.retryCount = 0
        voiceInputState.isInstructing = true
        voiceInputState.debugInfo = "Restarting voice input"

        let isFrench = languageManager?.currentLanguage == .french
        let message = isFrench
            ? "Recommençons. Quel est votre lieu de départ?"
            : "Let's start over. What is your starting location?"

        speakThenListen(message, delay: instructionDelay)
    }

    // MARK: - Error Handling

    private func handleExtractionFailure(_ type: String, _ text: String, _ mode: InputMode) {
        let retries = voiceInputState.retryCount + 1

        if retries >= voiceInputState.maxRetries {
            voiceInputState.currentMode = .none
            voiceInputState.errorMessage = "Max retries reached"
            voiceInputState.debugInfo = "Could not understand \(type). Please use settings."
            ttsManager?.speakPriority(
                "I couldn't understand your \(type). Please set it manually in settings."
            )
            return
        }

        voiceInputState.retryCount = retries

        let prompt: String
        if type == "source" {
            prompt = "I didn't understand. Please say your starting location clearly."
        } else {
            prompt = "I didn't understand. Please say your destination clearly."
        }

        voiceInputState.currentMode = mode
        voiceInputState.isInstructing = true
        voiceInputState.debugInfo = "Retry \(retries) for \(type)"

        speakThenListen(prompt, delay: retryDelay)
    }

    private func retryInput(_ type: String, mode: InputMode, prompt: String) {
        let retries = voiceInputState.retryCount + 1

        if retries >= voiceInputState.maxRetries {
            voiceInputState.currentMode = .none
            ttsManager?.speakPriority("Max retries reached. Please use settings.")
            return
        }

        voiceInputState.currentMode = mode
        voiceInputState.waitingForConfirmation = false
        voiceInputState.retryCount = retries
        voiceInputState.isInstructing = true
        voiceInputState.debugInfo = "Retry \(retries) for \(type)"

        speakThenListen(prompt, delay: retryDelay)
    }

    private func handleNoSpeech() {
        let prompt: String
        switch voiceInputState.currentMode {
        case .listeningSource:
            prompt = "I didn't hear anything. What is your starting location?"
        case .listeningDestination:
            prompt = "I didn't hear anything. Where do you want to go?"
        case .confirmingSource:
            prompt = "Please say yes or no. Is \(tempSource) correct?"
        case .confirmingDestination:
            prompt = "Please say yes or no. Is \(tempDestination) correct?"
        case .confirmingBoth:
            prompt = "Please say yes to confirm, or no to start over."
        case .none:
            return
        }

        voiceInputState.isInstructing = true
        speakThenListen(prompt, delay: confirmationDelay)
    }

    private func handleSpeechError() {
        let prompt: String
        switch voiceInputState.currentMode {
        case .listeningSource:
            prompt = "Let's try again. What is your starting location?"
        case .listeningDestination:
            prompt = "Let's try again. Where do you want to go?"
        default:
            prompt = "Let's try again."
        }

        voiceInputState.isInstructing = true
        speakThenListen(prompt, delay: retryDelay)
    }

    // MARK: - Location Extraction

    /// Extract a location name from spoken text using regex patterns and fuzzy POI matching
    private func extractLocation(_ text: String, expectedType: String) -> String {
        let cleanText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        print("VoiceNavigationManager: Extracting \(expectedType) from '\(cleanText)'")

        // Pattern 1: "source room 435" or "destination room 424"
        let pattern1 = "\(expectedType)\\s+(room\\s*\\d+)"
        if let range = cleanText.range(of: pattern1, options: .regularExpression) {
            var location = String(cleanText[range])
            // Remove the type prefix
            let prefixPattern = "\(expectedType)\\s+"
            if let prefixRange = location.range(of: prefixPattern, options: .regularExpression) {
                location.removeSubrange(prefixRange)
            }
            location = location.replacingOccurrences(of: " ", with: "")
            print("VoiceNavigationManager: Pattern 1 match: '\(location)'")
            return location
        }

        // Pattern 2: "source 435"
        let pattern2 = "\(expectedType)\\s+(\\d+)"
        if let range = cleanText.range(of: pattern2, options: .regularExpression) {
            var number = String(cleanText[range])
            let prefixPattern = "\(expectedType)\\s+"
            if let prefixRange = number.range(of: prefixPattern, options: .regularExpression) {
                number.removeSubrange(prefixRange)
            }
            let location = "room\(number)"
            print("VoiceNavigationManager: Pattern 2 match: '\(location)'")
            return location
        }

        // Pattern 3: Just "room 435" or "3120"
        let pattern3 = "(?:room\\s*)?(\\d{3,4})"
        if let range = cleanText.range(of: pattern3, options: .regularExpression) {
            var number = String(cleanText[range])
            // Remove "room " prefix if present
            let roomPrefix = "room\\s*"
            if let roomRange = number.range(of: roomPrefix, options: .regularExpression) {
                number.removeSubrange(roomRange)
            }
            let location = "room\(number)"
            print("VoiceNavigationManager: Pattern 3 match: '\(location)'")
            return location
        }

        // Pattern 4: Fuzzy match against known POI names
        if let matched = fuzzyMatchPOI(cleanText) {
            print("VoiceNavigationManager: Fuzzy POI match: '\(matched)'")
            return matched
        }

        // Pattern 5: Known keyword matching (elevator, restroom, etc.)
        let knownKeywords = ["elevator", "stairs", "staircase", "exit",
                             "entrance", "restroom", "bathroom", "washroom",
                             "lobby", "reception", "office", "classroom",
                             "lab", "library", "cafeteria", "kitchen"]

        for keyword in knownKeywords {
            if cleanText.contains(keyword) {
                if let poi = availablePOIs.first(where: {
                    $0.lowercased().contains(keyword)
                }) {
                    print("VoiceNavigationManager: Keyword match: '\(poi)'")
                    return poi
                }
            }
        }

        print("VoiceNavigationManager: No match found in '\(cleanText)'")
        return ""
    }

    /// Fuzzy match spoken text against available POI names
    private func fuzzyMatchPOI(_ text: String) -> String? {
        // Remove common speech prefixes
        let prefixPattern = "(?:source|destination|starting|going to|from|to|the|my)\\s*"
        let cleanText = text.lowercased()
            .replacingOccurrences(of: prefixPattern, with: "",
                                  options: .regularExpression, range: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanText.isEmpty else { return nil }

        var bestMatch: String?
        var bestScore: Double = 0

        for poi in availablePOIs {
            let poiLower = poi.lowercased()

            // Direct containment (user said "restroom", POI is "allgenderrestroom")
            if poiLower.contains(cleanText) || cleanText.contains(poiLower) {
                let minLen = Double(min(cleanText.count, poiLower.count))
                let maxLen = Double(max(cleanText.count, poiLower.count))
                let score = maxLen > 0 ? minLen / maxLen : 0
                if score > bestScore {
                    bestScore = score
                    bestMatch = poi
                }
            }

            // Word-level matching
            let textWords = Set(cleanText.split(separator: " ").map { String($0) })
            let poiWords = Set(poiLower.split(separator: " ").map { String($0) })
            let poiParts = Set(splitCamelCase(poi).map { $0.lowercased() })

            let allPoiWords = poiWords.union(poiParts)
            let intersection = textWords.intersection(allPoiWords)

            if !intersection.isEmpty {
                let score = Double(intersection.count) / Double(max(textWords.count, 1))
                if score > bestScore {
                    bestScore = score
                    bestMatch = poi
                }
            }
        }

        // Only return if we have a reasonable match (>= 40%)
        return bestScore >= 0.4 ? bestMatch : nil
    }

    /// Split "allGenderRestroom" or concatenated names into word components
    private func splitCamelCase(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for char in text {
            if char.isUppercase && !current.isEmpty {
                words.append(current)
                current = String(char)
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    // MARK: - Response Detection

    private func isPositiveResponse(_ text: String) -> Bool {
        let cleaned = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let positives = ["yes", "yeah", "yep", "correct", "right", "true",
                         "affirmative", "sure", "ok", "okay", "that's right",
                         "oui", "exactement"]
        return positives.contains(where: { cleaned.contains($0) })
    }

    private func isNegativeResponse(_ text: String) -> Bool {
        let cleaned = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let negatives = ["no", "nope", "wrong", "incorrect", "false",
                         "try again", "retry", "non", "pas correct"]
        return negatives.contains(where: { cleaned.contains($0) })
    }

    // MARK: - TTS + Listen Coordination

    /// Speak a prompt via TTS, then start listening after a delay
    private func speakThenListen(_ message: String, delay: TimeInterval) {
        ttsManager?.speakPriority(message)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            guard self.voiceInputState.currentMode != .none else { return }
            self.voiceInputState.isInstructing = false
            self.startListening()
        }
    }
}




