//
//  ConversationManager.swift
//  IndoorNavigationTACME
//
//  Manages AI conversation: SFSpeechRecognizer → OpenAI GPT → AVSpeechSynthesizer (TTS)
//
//  ROOT CAUSE FIXES vs previous version:
//  1. TTSManager sets audio session to .playback.  Recording tap then gets zero-byte
//     buffers because the engine's input node format is wrong.
//     FIX: Stop the TTS synthesizer, switch session to .playAndRecord, call
//          audioEngine.reset() + inputNode.removeTap() before EVERY fresh tap install.
//  2. inputNode.outputFormat(forBus:0) can return a mismatched format on real hardware.
//     FIX: Use inputNode.inputFormat(forBus:0) which returns the hardware's native rate.
//  3. Permissions were never explicitly checked at runtime.
//     FIX: Request SFSpeechRecognizer + microphone auth in configure().
//  4. After TTS finishes the auto-restart fired immediately while the audio session was
//     still held in .playback mode.
//     FIX: 0.6 s settling delay + session switch happens inside performStartListening.
//

import Foundation
import Speech
import AVFoundation
import Combine

final class ConversationManager: ObservableObject {

    // MARK: - Published

    @Published var conversationState = ConversationState()
    /// Normalised microphone energy 0…1 — drives the orb animation.
    @Published var audioLevel: Float = 0.0

    // MARK: - Private

    private weak var ttsManager: TTSManager?
    private weak var languageManager: LanguageManager?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var sourceLocation: String?
    private var destinationLocation: String?
    private var routeData: String?

    /// Rolling GPT message history (system prompt rebuilt each call).
    private var chatHistory: [[String: String]] = []

    /// Combine subscription watching TTS speaking state.
    private var ttsSub: AnyCancellable?
    private var ttsWasSpeaking = false

    /// Guards against overlapping restart schedules.
    private var restartScheduled = false
    private var silenceTimer: Timer?
    private let silenceDuration: TimeInterval = 1.2

    // MARK: - Init

    init() {}

    // MARK: - Configuration (call once from App setup)

    func configure(ttsManager: TTSManager, languageManager: LanguageManager) {
        self.ttsManager    = ttsManager
        self.languageManager = languageManager
        requestPermissions()
        observeTTS(ttsManager: ttsManager)
        print("ConversationManager: configured (OpenAI backend)")
    }

    // MARK: - Public API

    func startConversationMode() {
        DispatchQueue.main.async {
            self.conversationState.isActive = true
        }
        chatHistory.removeAll()
        ttsWasSpeaking = false
        restartScheduled = false
        print("ConversationManager: Conversation mode ON")

        // Speak greeting, then the TTS observer auto-starts listening when it finishes.
        ttsManager?.speakPriority("Conversation mode activated. How can I help you navigate?")
        // Safety fallback — if TTS observer misses the transition, start after 3.5 s.
        scheduleRestart(after: 3.5)
    }

    func stopConversationMode() {
        print("ConversationManager: Conversation mode OFF")
        hardStopListening()
        restartScheduled = false
        ttsWasSpeaking = false

        DispatchQueue.main.async {
            self.conversationState = ConversationState()
            self.audioLevel = 0
        }
        chatHistory.removeAll()
        ttsManager?.speakPriority("Conversation mode deactivated")
    }

    /// Begin a recognition cycle.
    func startListening() {
        guard conversationState.isActive,
              !conversationState.isListening,
              !conversationState.isProcessing else { return }

        restartScheduled = false
        print("ConversationManager: startListening")

        // Stop TTS first so its audio session doesn't conflict.
        ttsManager?.stop()

        DispatchQueue.main.async {
            self.conversationState.isListening = true
            self.conversationState.currentSpeechText = ""
            self.conversationState.errorMessage = nil
        }

        // Small delay so TTS audio session fully releases before we switch category.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.25) {
            self.performStartListening()
        }
    }
    
    func stopListening() {
        hardStopListening()
    }

    // MARK: - Context setters

    func setLocations(source: String, destination: String) {
        sourceLocation = source
        destinationLocation = destination
    }

    func setRouteData(_ data: String) {
        routeData = data
        DispatchQueue.main.async { self.conversationState.hasRouteData = true }
    }

    /// Process text directly (used internally after recognition, and for testing).
    func processTextInput(_ userInput: String) {
        let text = userInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, conversationState.isActive else { return }

        print("ConversationManager: processing → \"\(text)\"")
        chatHistory.append(["role": "user", "content": text])

        DispatchQueue.main.async {
            self.conversationState.isProcessing = true
            self.conversationState.currentSpeechText = text
        }

        Task { await queryOpenAI() }
    }

    // MARK: - Private: permissions

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            print("ConversationManager: SFSpeechRecognizer auth → \(status.rawValue)")
        }
        AVAudioApplication.requestRecordPermission { granted in
            print("ConversationManager: Microphone permission → \(granted)")
        }

        let locale = languageManager?.getCurrentLocale() ?? Locale(identifier: "en-US")
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        print("ConversationManager: SFSpeechRecognizer ready=\(speechRecognizer?.isAvailable == true) locale=\(locale.identifier)")
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()

        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceDuration, repeats: false) { [weak self] _ in
            self?.handleSilenceDetected()
        }
    }
    
    private func handleSilenceDetected() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        let text = conversationState.currentSpeechText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            startListening()
            return
        }

        hardStopListening()
        processTextInput(text)
    }

    // MARK: - Private: audio engine + recognition

    private func performStartListening() {
        // ── 1. Tear down any previous session completely ──────────────
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        // CRITICAL: removeTap before reset, otherwise reset can crash
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.reset()

        // ── 2. Switch audio session to playAndRecord ──────────────────
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.duckOthers, .allowBluetooth, .defaultToSpeaker]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("ConversationManager: Audio session error: \(error)")
            DispatchQueue.main.async { self.conversationState.isListening = false }
            return
        }

        // ── 3. Create recognition request ─────────────────────────────
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false   // server-side for better accuracy
        // Hint: longer silence = more time for the user to pause between phrases
        if #available(iOS 17, *) {
            request.addsPunctuation = false
        }
        recognitionRequest = request

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("ConversationManager: SFSpeechRecognizer not available")
            DispatchQueue.main.async { self.conversationState.isListening = false }
            return
        }

        // ── 4. Start recognition task ─────────────────────────────────
        recognitionTask = recognizer.recognitionTask(
            with: request
        ) { [weak self] result, error in

            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString

                DispatchQueue.main.async {
                    self.conversationState.currentSpeechText = text
                }

                self.resetSilenceTimer()
            }

            if let error = error as NSError? {
                print("ConversationManager: recognition error \(error.domain)/\(error.code)")
                self.hardStopListening()
            }
        }

        // ── 5. Install audio tap ───────────────────────────────────────
        // Use inputFormat(forBus:) — NOT outputFormat — to get the hardware's
        // native sample rate. This is the fix for zero-byte buffers.
        let inputNode = audioEngine.inputNode
        let hwFormat  = inputNode.inputFormat(forBus: 0)

        print("ConversationManager: hw format sr=\(hwFormat.sampleRate) ch=\(hwFormat.channelCount)")

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            request.append(buffer)

            // Compute RMS for orb animation
            guard let data = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            vDSP_svesq(data, 1, &sum, vDSP_Length(count))
            let rms   = sqrtf(sum / Float(count))
            let level = min(rms * 15.0, 1.0)
            DispatchQueue.main.async { self?.audioLevel = level }
        }

        // ── 6. Start engine ───────────────────────────────────────────
        audioEngine.prepare()
        do {
            try audioEngine.start()
            print("ConversationManager: AVAudioEngine running ✓")
        } catch {
            print("ConversationManager: Engine start failed: \(error)")
            recognitionRequest = nil
            DispatchQueue.main.async { self.conversationState.isListening = false }
        }
    }

    /// Hard-stop — used on deactivation or before a fresh listen cycle.
    private func hardStopListening() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        cleanupAudioEngine()
        DispatchQueue.main.async {
            self.conversationState.isListening = false
            self.audioLevel = 0
        }
    }

    private func cleanupAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    // MARK: - Private: OpenAI

    private func queryOpenAI() async {
        var messages: [[String: String]] = [["role": "system", "content": buildSystemPrompt()]]
        messages.append(contentsOf: chatHistory.suffix(12))  // keep context window manageable

        do {
            let reply = try await OpenAIService.shared.chatCompletion(messages: messages, maxTokens: 500)
            print("ConversationManager: GPT reply → \"\(reply.prefix(80))\"")
            chatHistory.append(["role": "assistant", "content": reply])
            await deliverResponse(reply)
        } catch {
            print("ConversationManager: OpenAI error → \(error)")
            let fallback = "I'm having trouble connecting. Please try again."
            chatHistory.append(["role": "assistant", "content": fallback])
            await deliverResponse(fallback)
        }
    }

    @MainActor
    private func deliverResponse(_ text: String) {
        conversationState.isProcessing = false
        conversationState.currentMessage = text
        conversationState.messages.append(
            ChatMessage(content: text, isUser: false)
        )
        // Speak — TTS observer will auto-restart listening when finished.
        ttsWasSpeaking = false
        ttsManager?.speakPriority(text)
    }

    // MARK: - Private: TTS observer → auto-restart listening

    private func observeTTS(ttsManager: TTSManager) {
        ttsSub = ttsManager.$ttsState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }

                if state.isSpeaking {
                    self.ttsWasSpeaking = true
                } else if self.ttsWasSpeaking {
                    self.ttsWasSpeaking = false
                    guard self.conversationState.isActive,
                          !self.conversationState.isListening,
                          !self.conversationState.isProcessing else { return }
                    // Give audio session 0.6 s to fully release from TTS playback
                    self.scheduleRestart(after: 0.6)
                }
            }
    }

    private func scheduleRestart(after delay: TimeInterval) {
        guard conversationState.isActive, !restartScheduled else { return }
        restartScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.conversationState.isActive else { return }
            self.restartScheduled = false
            if !self.conversationState.isListening, !self.conversationState.isProcessing {
                self.startListening()
            }
        }
    }

    // MARK: - Private: system prompt

    private func buildSystemPrompt() -> String {
        var ctx = ""
        if let src = sourceLocation, let dst = destinationLocation {
            ctx += "User is navigating from '\(src)' to '\(dst)'. "
        }
        if let route = routeData {
            ctx += "Route: \(route.prefix(1200)). "
        }
        return """
        You are a concise indoor navigation assistant for visually impaired users. \
        \(ctx)\
        Reply in 1–3 short spoken sentences only. \
        No markdown, no bullet points, no special characters — plain speech only. \
        Prioritise clarity and safety.
        """
    }
}

// vDSP import for RMS calculation
import Accelerate
