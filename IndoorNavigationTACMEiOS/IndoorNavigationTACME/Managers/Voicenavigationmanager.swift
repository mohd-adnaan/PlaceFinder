//
//  VoiceNavigationManager.swift
//  IndoorNavigationTACME
//
//  Voice-controlled navigation input manager.
//  Allows users to set source and destination via speech,
//  with confirmation flow and fuzzy POI matching.
//

import Foundation
import Speech
import AVFoundation
import AudioToolbox   // ← For SystemSoundID beeps (accessibility feedback)
import Combine
import UIKit

class VoiceNavigationManager: ObservableObject {

    // MARK: - Types

    enum InputMode: Equatable {
        case idle
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
        var currentMode: InputMode = .idle
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

    /// 0…1 microphone RMS, updated in real time while listening.
    /// Drives the audio-reactive particle orb on the landing page so blind
    /// users still get sighted-companion visual feedback (and so the orb
    /// matches the responsiveness sighted users expect from voice UIs).
    @Published var audioLevel: Float = 0.0

    // MARK: - Private Properties

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // ═══════════════════════════════════════════════════════════════════
    // KEY FIX: This MUST be `var`, not `let`.
    //
    // AVAudioEngine created at app launch caches "no input available"
    // because the audio session starts in .playback mode (for TTS).
    // When we later switch to .playAndRecord, the OLD engine still
    // returns 0 Hz / 0 channels for inputNode.outputFormat.
    //
    // The fix: create a FRESH AVAudioEngine AFTER configuring the
    // audio session for recording. The new engine queries the current
    // hardware route and gets the real microphone format.
    // ═══════════════════════════════════════════════════════════════════
    private var audioEngine = AVAudioEngine()

    private var ttsManager: TTSManager?
    private var languageManager: LanguageManager?
    private var ttsStateSubscription: AnyCancellable?

    private var tempSource: String = ""
    private var tempDestination: String = ""
    private var availablePOIs: [String] = []
    private var feedbackGenerator: UIImpactFeedbackGenerator?

    // Session counter to invalidate stale speakThenListen callbacks
    private var sessionCounter: Int = 0
    private var pendingListenSession: Int?
    private var delayedListenWorkItem: DispatchWorkItem?
    private var delayedStartCheckWorkItem: DispatchWorkItem?
    private var delayedCompletionFallbackWorkItem: DispatchWorkItem?
    private var ttsWasSpeaking: Bool = false

    // Silence timeout: treat last partial result as final after this duration
    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 1.15
    private var lastPartialResult: String = ""

    private let instructionDelay: TimeInterval = 1.0
    private let confirmationDelay: TimeInterval = 0.9
    private let retryDelay: TimeInterval = 0.8

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
        observeTTSState(ttsManager)
        print("VoiceNavigationManager: Dependencies configured")
    }

    // MARK: - Public Methods

    /// Begin the voice-driven source/destination capture flow.
    /// - Parameters:
    ///   - poiNames: Resolvable POI names from the current map.
    ///   - isStepCalibrated: Whether the device has a valid stored gait calibration.
    ///                       When `false`, the flow is aborted with a spoken instruction
    ///                       telling the user to calibrate first — voice navigation
    ///                       depends on accurate step length, so starting before
    ///                       calibration produces unreliable distance estimates.
    ///                       Defaults to `true` to preserve any existing call sites.
    func startVoiceInput(poiNames: [String], isStepCalibrated: Bool = true) {
        availablePOIs = poiNames
        tempSource = ""
        tempDestination = ""
        sessionCounter += 1

        let isFrench = languageManager?.currentLanguage == .french

        // ─── Calibration gate ────────────────────────────────────────────
        // First-time users (no stored beta) must calibrate before navigation,
        // otherwise step distances are estimated from the default factor and
        // the route falls out of sync within a few segments. Speak a clear
        // instruction and stay idle so a single tap doesn't fight the prompt.
        if !isStepCalibrated {
            voiceInputState = VoiceInputState()
            voiceInputState.currentMode = .idle
            voiceInputState.debugInfo = "Calibration required before voice navigation"

            let calibrationPrompt = isFrench
                ? "Calibration requise. Veuillez ouvrir les paramètres et marcher vingt mètres pour calibrer votre démarche, puis réessayez."
                : "Calibration required. Please open settings and walk twenty meters to calibrate your stride, then try again."
            ttsManager?.speakPriority(calibrationPrompt)
            print("VoiceNavigationManager: Calibration gate triggered — flow aborted")
            return
        }

        voiceInputState = VoiceInputState()
        voiceInputState.isReady = true
        voiceInputState.currentMode = .listeningSource
        voiceInputState.isInstructing = true
        voiceInputState.debugInfo = "Starting voice navigation setup"

        let prompt = isFrench
            ? "Quel est votre lieu de départ?"
            : "What is your starting location?"

        speakThenListen(prompt, delay: instructionDelay)
    }

    func cancelVoiceInput() {
        sessionCounter += 1
        pendingListenSession = nil
        delayedListenWorkItem?.cancel()
        delayedListenWorkItem = nil
        delayedStartCheckWorkItem?.cancel()
        delayedStartCheckWorkItem = nil
        delayedCompletionFallbackWorkItem?.cancel()
        delayedCompletionFallbackWorkItem = nil
        invalidateSilenceTimer()
        forceStopListening()
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
        guard voiceInputState.currentMode != .idle else { return }

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
        // Fully clean up any previous listening state
        forceStopListening()

        guard voiceInputState.currentMode != .idle else { return }
        let capturedSession = sessionCounter

        // ─── Step 1: Configure audio session for recording ───
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement,
                                         options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("VoiceNavigationManager: Audio session error: \(error)")
            voiceInputState.errorMessage = "Audio setup failed"
            return
        }

        // ─── Step 2: Create a FRESH AVAudioEngine ───
        // This is THE fix. A new engine queries the CURRENT hardware route,
        // which now includes the microphone input thanks to .playAndRecord.
        audioEngine = AVAudioEngine()

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Safety check (should no longer be needed, but belt-and-suspenders)
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            print("VoiceNavigationManager: Audio format invalid even after fresh engine: \(recordingFormat.sampleRate) Hz, \(recordingFormat.channelCount) ch — retrying in 500ms")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self, self.sessionCounter == capturedSession else { return }
                self.performStartListening()
            }
            return
        }

        print("VoiceNavigationManager: Audio format OK — \(recordingFormat.sampleRate) Hz, \(recordingFormat.channelCount) ch")

        // ─── Step 3: Create recognition request ───
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

        // ─── Step 4: Install audio tap ───
        // Tap pulls every microphone buffer. We forward it to the recognizer
        // and ALSO compute a per-buffer RMS, which the LandingPageView orb
        // reads to drive its breathing animation. Same scaling as
        // ConversationManager (rms * 15) so the two managers feel uniform.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            guard let self = self,
                  let data = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            vDSP_svesq(data, 1, &sum, vDSP_Length(count))
            let rms   = sqrtf(sum / Float(count))
            let level = min(rms * 15.0, 1.0)
            DispatchQueue.main.async { self.audioLevel = level }
        }

        // ─── Step 5: Start engine ───
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("VoiceNavigationManager: Audio engine start error: \(error)")
            voiceInputState.errorMessage = "Microphone error"
            inputNode.removeTap(onBus: 0)
            return
        }

        // ─── Step 6: Start recognition task ───
        voiceInputState.isListening = true
        voiceInputState.debugInfo = "Listening..."
        lastPartialResult = ""

        // ═══════════════════════════════════════════════════════════════════
        // ACCESSIBILITY FIX: Play an audible "ready" beep so visually
        // impaired users know the microphone is ACTIVE and they can speak.
        //
        // Root cause: Users were saying "yes" immediately after hearing the
        // TTS prompt, but SFSpeechRecognizer wasn't listening yet. The beep
        // eliminates this timing mismatch — speak AFTER the beep, not before.
        //
        // Sound 1113 = "begin recording" system tone (short, recognizable).
        // Haptic is kept as a secondary cue for users who can feel it.
        // ═══════════════════════════════════════════════════════════════════
        playListeningReadyBeep()
        feedbackGenerator?.impactOccurred()

        let currentSession = sessionCounter

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    guard let self = self else { return }
                    guard self.sessionCounter == currentSession else { return }

                    if let result = result {
                        let text = result.bestTranscription.formattedString
                        let isFinal = result.isFinal

                        DispatchQueue.main.async {
                            self.voiceInputState.lastResult = text
                            self.voiceInputState.debugInfo = "Heard: \(text)"
                            self.lastPartialResult = text

                            if isFinal {
                                self.invalidateSilenceTimer()
                                self.forceStopListening()
                                self.sessionCounter += 1 // 🛑 FIX: Prevent duplicate callbacks
                                self.processRecognitionResult(text)
                            } else {
                                self.resetSilenceTimer(session: currentSession)
                            }
                        }
                    }

                    if let error = error {
                        guard self.sessionCounter == currentSession else { return }

                        DispatchQueue.main.async {
                            self.invalidateSilenceTimer()
                            self.forceStopListening()
                            self.sessionCounter += 1 // 🛑 FIX: Prevent cascading errors

                            let nsError = error as NSError
                            if nsError.code == 203 || nsError.code == 1110 {
                                if !self.lastPartialResult.isEmpty {
                                    self.processRecognitionResult(self.lastPartialResult)
                                } else {
                                    self.handleNoSpeech()
                                }
                            } else {
                                self.voiceInputState.errorMessage = "Recognition error"
                                self.voiceInputState.debugInfo = "Error — retrying"
                                if !self.lastPartialResult.isEmpty {
                                    self.processRecognitionResult(self.lastPartialResult)
                                } else {
                                    self.handleSpeechError()
                                }
                            }
                        }
                    }
                }
    }

    /// Force-stop all audio and recognition — safe to call multiple times
    private func forceStopListening() {
        invalidateSilenceTimer()

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        // removeTap is safe even if no tap is installed
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        voiceInputState.isListening = false
        // Reset orb-driving level so the particle animation falls back to
        // its idle breath rather than freezing at the last seen value.
        audioLevel = 0
    }

    // MARK: - Silence Timer

    private func resetSilenceTimer(session: Int) {
            invalidateSilenceTimer()
            silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                guard self.sessionCounter == session else { return }
                guard !self.lastPartialResult.isEmpty else { return }

                print("VoiceNavigationManager: Silence timeout → treating partial as final: '\(self.lastPartialResult)'")
                self.forceStopListening()
                self.sessionCounter += 1 // 🛑 FIX: Stop SFSpeechRecognizer from sending a late cancellation error
                self.processRecognitionResult(self.lastPartialResult)
            }
        }

    private func invalidateSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    // MARK: - Result Processing

    private func processRecognitionResult(_ text: String) {
        let currentMode = voiceInputState.currentMode
        lastPartialResult = ""

        switch currentMode {
        case .listeningSource:
            let extracted = extractLocation(text, expectedType: "source")
            if !extracted.isEmpty {
                tempSource = extracted
                let spokenSource = speechFriendlyLocation(extracted)
                let isFrench = languageManager?.currentLanguage == .french
                let confirmMessage = isFrench
                    ? "Votre point de départ est \(spokenSource)?"
                    : "Is your starting location \(spokenSource)?"

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
                let spokenDestination = speechFriendlyLocation(extracted)
                let isFrench = languageManager?.currentLanguage == .french
                let confirmMessage = isFrench
                    ? "Votre destination est \(spokenDestination)?"
                    : "Is your destination \(spokenDestination)?"

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
                let clarify = "Please say yes if \(speechFriendlyLocation(tempSource)) is correct, or no to try again."
                voiceInputState.isInstructing = true
                speakThenListen(clarify, delay: confirmationDelay)
            }

        case .confirmingDestination:
            if isPositiveResponse(text) {
                completeVoiceInput()
            } else if isNegativeResponse(text) {
                retryInput("destination", mode: .listeningDestination,
                           prompt: "Again. Where do you want to go?")
            } else {
                let clarify = "Please say yes if \(speechFriendlyLocation(tempDestination)) is correct, or no to try again."
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

        case .idle:
            break
        }
    }

    // MARK: - Confirmation Flow

    private func showFinalConfirmation() {
        let isFrench = languageManager?.currentLanguage == .french
        let spokenSource = speechFriendlyLocation(tempSource)
        let spokenDestination = speechFriendlyLocation(tempDestination)
        let finalMessage = isFrench
            ? "Parfait! Route de \(spokenSource) à \(spokenDestination)."
            : "Perfect! Route from \(spokenSource) to \(spokenDestination)."

        voiceInputState.currentMode = .confirmingBoth
        voiceInputState.confirmationPrompt = finalMessage
        voiceInputState.destination = tempDestination
        voiceInputState.isInstructing = true
        voiceInputState.debugInfo = "Final confirmation needed"

        speakThenListen(finalMessage, delay: instructionDelay)
    }

    private func completeVoiceInput() {
        print("VoiceNavigationManager: Completed — \(tempSource) → \(tempDestination)")
        sessionCounter += 1

        voiceInputState.source = tempSource
        voiceInputState.destination = tempDestination
        voiceInputState.isComplete = true
        voiceInputState.currentMode = .idle
        voiceInputState.waitingForConfirmation = false
        voiceInputState.isInstructing = false
        voiceInputState.debugInfo = "Voice input complete!"

        let isFrench = languageManager?.currentLanguage == .french
        let spokenSource = speechFriendlyLocation(tempSource)
        let spokenDestination = speechFriendlyLocation(tempDestination)
        let successMessage = isFrench
            ? "Excellent! Navigation de \(spokenSource) à \(spokenDestination). Pointez votre caméra vers un code QR."
            : "Excellent! Navigation from \(spokenSource) to \(spokenDestination). Point your camera at any QR code."

        ttsManager?.speakPriority(successMessage)
    }

    private func restartVoiceInput() {
        sessionCounter += 1
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
            voiceInputState.currentMode = .idle
            voiceInputState.errorMessage = "Max retries reached"
            voiceInputState.debugInfo = "Could not understand \(type). Please use settings."
            ttsManager?.speakPriority(
                "I couldn't understand your \(type). Please set it manually in settings."
            )
            return
        }

        voiceInputState.retryCount = retries
        let prompt = type == "source"
            ? "I didn't understand. Please say your starting location clearly."
            : "I didn't understand. Please say your destination clearly."

        voiceInputState.currentMode = mode
        voiceInputState.isInstructing = true
        voiceInputState.debugInfo = "Retry \(retries) for \(type)"

        speakThenListen(prompt, delay: retryDelay)
    }

    private func retryInput(_ type: String, mode: InputMode, prompt: String) {
        let retries = voiceInputState.retryCount + 1

        if retries >= voiceInputState.maxRetries {
            voiceInputState.currentMode = .idle
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
            // 🛑 FIX: Add retry limits
            let retries = voiceInputState.retryCount + 1
            if retries >= voiceInputState.maxRetries {
                voiceInputState.currentMode = .idle
                ttsManager?.speakPriority("I'm having trouble hearing you. Max retries reached. Please use settings.")
                return
            }
            voiceInputState.retryCount = retries

            let prompt: String
            switch voiceInputState.currentMode {
            case .listeningSource:
                prompt = "I didn't hear anything. What is your starting location?"
            case .listeningDestination:
                prompt = "I didn't hear anything. Where do you want to go?"
            case .confirmingSource:
                prompt = "Please say yes or no. Is \(speechFriendlyLocation(tempSource)) correct?"
            case .confirmingDestination:
                prompt = "Please say yes or no. Is \(speechFriendlyLocation(tempDestination)) correct?"
            case .confirmingBoth:
                prompt = "Please say yes to confirm, or no to start over."
            case .idle:
                return
            }
            voiceInputState.isInstructing = true
            speakThenListen(prompt, delay: confirmationDelay)
        }

        private func handleSpeechError() {
            // 🛑 FIX: Add retry limits
            let retries = voiceInputState.retryCount + 1
            if retries >= voiceInputState.maxRetries {
                voiceInputState.currentMode = .idle
                ttsManager?.speakPriority("Speech error. Max retries reached. Please use settings.")
                return
            }
            voiceInputState.retryCount = retries

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

    private func extractLocation(_ text: String, expectedType: String) -> String {
        let cleanText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        print("VoiceNavigationManager: Extracting \(expectedType) from '\(cleanText)'")

        // Pattern: "source room 435"
        let p1 = "\(expectedType)\\s+(room\\s*\\d+)"
        if let range = cleanText.range(of: p1, options: .regularExpression) {
            var loc = String(cleanText[range])
            if let pr = loc.range(of: "\(expectedType)\\s+", options: .regularExpression) {
                loc.removeSubrange(pr)
            }
            return loc.replacingOccurrences(of: " ", with: "")
        }

        // Pattern: "source 435"
        let p2 = "\(expectedType)\\s+(\\d+)"
        if let range = cleanText.range(of: p2, options: .regularExpression) {
            var num = String(cleanText[range])
            if let pr = num.range(of: "\(expectedType)\\s+", options: .regularExpression) {
                num.removeSubrange(pr)
            }
            return "room\(num)"
        }

        // Pattern: "room 435" or just "3120"
        let p3 = "(?:room\\s*)?(\\d{3,4})"
        if let range = cleanText.range(of: p3, options: .regularExpression) {
            var num = String(cleanText[range])
            if let rr = num.range(of: "room\\s*", options: .regularExpression) {
                num.removeSubrange(rr)
            }
            return "room\(num)"
        }

        // Fuzzy POI match
        if let matched = fuzzyMatchPOI(cleanText) { return matched }

        // Keyword match
        let keywords = ["elevator", "stairs", "staircase", "exit",
                        "entrance", "restroom", "bathroom", "washroom",
                        "lobby", "reception", "office", "classroom",
                        "lab", "library", "cafeteria", "kitchen",
                        "gender", "computer", "science", "workstation"]

        for kw in keywords {
            if cleanText.contains(kw) {
                if let poi = availablePOIs.first(where: { $0.lowercased().contains(kw) }) {
                    return poi
                }
            }
        }

        return ""
    }

    private func fuzzyMatchPOI(_ text: String) -> String? {
        let prefixPattern = "(?:source|destination|starting|going to|from|to|the|my)\\s*"
        let cleanText = text.lowercased()
            .replacingOccurrences(of: prefixPattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanText.isEmpty else { return nil }

        var bestMatch: String?
        var bestScore: Double = 0

        for poi in availablePOIs {
            let poiLower = poi.lowercased()

            // Direct containment
            if poiLower.contains(cleanText) || cleanText.contains(poiLower) {
                let score = Double(min(cleanText.count, poiLower.count)) /
                            Double(max(cleanText.count, poiLower.count))
                if score > bestScore { bestScore = score; bestMatch = poi }
            }

            // Word-level matching
            let textWords = Set(cleanText.split(separator: " ").map { String($0) })
            let poiParts = Set(splitCamelCase(poi).map { $0.lowercased() })
            let poiWords = Set(poiLower.split(separator: " ").map { String($0) })
            let allPoiWords = poiWords.union(poiParts)
            let intersection = textWords.intersection(allPoiWords)

            if !intersection.isEmpty {
                let score = Double(intersection.count) / Double(max(textWords.count, 1))
                if score > bestScore { bestScore = score; bestMatch = poi }
            }
        }

        return bestScore >= 0.3 ? bestMatch : nil
    }

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

    private func speechFriendlyLocation(_ text: String) -> String {
        let spaced = text
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([A-Za-z])([0-9])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([0-9])([A-Za-z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")

        if spaced.lowercased().hasPrefix("room") {
            return spaced.replacingOccurrences(of: "room", with: "room ", options: [.caseInsensitive])
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return spaced
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Audible Feedback

    /// Play a short system tone to signal "microphone is active — speak now".
    ///
    /// This is critical for visually impaired users who cannot see the red
    /// "Listening" indicator. Without this beep, users speak before the
    /// recognizer is ready, causing their response to be lost.
    ///
    /// Sound 1113 = "begin recording" beep (gentle, non-intrusive).
    /// Falls back to 1057 (tock) if 1113 is unavailable on the device.
    private func playListeningReadyBeep() {
        AudioServicesPlaySystemSound(1113)
    }

    // MARK: - Response Detection

    private func isPositiveResponse(_ text: String) -> Bool {
        let cleaned = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return ["yes", "yeah", "yep", "correct", "right", "true",
                "affirmative", "sure", "ok", "okay", "that's right",
                "oui", "exactement"].contains(where: { cleaned.contains($0) })
    }

    private func isNegativeResponse(_ text: String) -> Bool {
        let cleaned = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return ["no", "nope", "wrong", "incorrect", "false",
                "try again", "retry", "non", "pas correct"].contains(where: { cleaned.contains($0) })
    }

    // MARK: - TTS + Listen Coordination

    private func speakThenListen(_ message: String, delay: TimeInterval) {
        delayedListenWorkItem?.cancel()
        delayedListenWorkItem = nil
        delayedStartCheckWorkItem?.cancel()
        delayedStartCheckWorkItem = nil
        delayedCompletionFallbackWorkItem?.cancel()
        delayedCompletionFallbackWorkItem = nil

        voiceInputState.isInstructing = true
        ttsWasSpeaking = false
        ttsManager?.speakPriority(message)
        let capturedSession = sessionCounter
        pendingListenSession = capturedSession

        // If TTS did not actually start (filtered/skipped), begin listening after a short grace period.
        let startCheck = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.pendingListenSession == capturedSession else { return }
            let stillNotSpeaking = self.ttsManager?.ttsState.isSpeaking != true
            if stillNotSpeaking && !self.ttsWasSpeaking {
                self.schedulePendingListen(for: capturedSession, delay: 0.12)
            }
        }
        delayedStartCheckWorkItem = startCheck
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: startCheck)

        // Absolute failsafe: if callbacks are missed, avoid hanging forever.
        let words = max(3, message.split(separator: " ").count)
        let estimatedSpeech = min(9.0, max(2.2, Double(words) * 0.33))
        let fallbackDelay = max(estimatedSpeech + 0.6, delay)
        let completionFallback = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.pendingListenSession == capturedSession else { return }
            self.schedulePendingListen(for: capturedSession, delay: 0.12)
        }
        delayedCompletionFallbackWorkItem = completionFallback
        DispatchQueue.main.asyncAfter(deadline: .now() + fallbackDelay, execute: completionFallback)
    }

    private func observeTTSState(_ ttsManager: TTSManager) {
        ttsStateSubscription = ttsManager.$ttsState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }

                if state.isSpeaking {
                    self.delayedStartCheckWorkItem?.cancel()
                    self.delayedStartCheckWorkItem = nil
                    self.ttsWasSpeaking = true
                    return
                }

                // TTS transitioned from speaking -> stopped; start listening quickly.
                if self.ttsWasSpeaking {
                    self.ttsWasSpeaking = false
                    self.delayedStartCheckWorkItem?.cancel()
                    self.delayedStartCheckWorkItem = nil
                    self.delayedCompletionFallbackWorkItem?.cancel()
                    self.delayedCompletionFallbackWorkItem = nil
                    if let pending = self.pendingListenSession {
                        self.schedulePendingListen(for: pending, delay: 0.15)
                    }
                }
            }
    }

    private func schedulePendingListen(for session: Int, delay: TimeInterval) {
        delayedListenWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.pendingListenSession == session else { return }
            guard self.sessionCounter == session else {
                print("VoiceNavigationManager: Stale callback ignored")
                return
            }
            guard self.voiceInputState.currentMode != .idle else { return }

            self.pendingListenSession = nil
            self.delayedStartCheckWorkItem?.cancel()
            self.delayedStartCheckWorkItem = nil
            self.delayedCompletionFallbackWorkItem?.cancel()
            self.delayedCompletionFallbackWorkItem = nil
            self.voiceInputState.isInstructing = false
            self.startListening()
        }

        delayedListenWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

// vDSP import for RMS calculation (audio-reactive orb)
import Accelerate
