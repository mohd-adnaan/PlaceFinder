//
//  ConversationManager.swift
//  IndoorNavigationTACME
//


import Foundation
import Speech
import AVFoundation
import Combine

/// Manages AI conversation features for voice-based navigation queries
class ConversationManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var conversationState = ConversationState()
    
    // MARK: - Private Properties
    
    private var ttsManager: TTSManager?
    private var languageManager: LanguageManager?
    
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // Route context for navigation queries
    private var routeData: String?
    private var sourceLocation: String?
    private var destinationLocation: String?
    
    // MARK: - Initialization
    
    init() {
        setupSpeechRecognizer()
        print("ConversationManager: Initialized")
    }
    
    // MARK: - Configuration
    
    /// Configure with required dependencies
    func configure(ttsManager: TTSManager, languageManager: LanguageManager) {
        self.ttsManager = ttsManager
        self.languageManager = languageManager
        
        // Update speech recognizer locale based on language
        updateSpeechRecognizerLocale()
        
        print("ConversationManager: Configured with dependencies")
    }
    
    // MARK: - Public Methods
    
    /// Start conversation mode
    func startConversationMode() {
        print("ConversationManager: Starting conversation mode")
        
        conversationState = ConversationState(isActive: true)
        
        // Announce activation
        let message = languageManager?.getString("Conversation mode activated. How can I help you navigate?") ??
                     "Conversation mode activated. How can I help you navigate?"
        ttsManager?.speakPriority(message)
        
        // Request speech authorization
        requestSpeechAuthorization()
    }
    
    /// Stop conversation mode
    func stopConversationMode() {
        print("ConversationManager: Stopping conversation mode")
        
        stopListening()
        conversationState = ConversationState()
        sourceLocation = nil
        destinationLocation = nil
        routeData = nil
        
        let message = languageManager?.getString("Conversation mode deactivated") ?? "Conversation mode deactivated"
        ttsManager?.speak(message)
    }
    
    /// Start listening for voice input
    func startListening() {
        guard conversationState.isActive else {
            print("ConversationManager: Cannot listen - conversation not active")
            return
        }
        
        // Check authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.performStartListening()
                case .denied:
                    self?.handleError("Speech recognition denied. Please enable it in Settings.")
                case .restricted:
                    self?.handleError("Speech recognition is restricted on this device.")
                case .notDetermined:
                    self?.handleError("Speech recognition authorization not determined.")
                @unknown default:
                    break
                }
            }
        }
    }
    
    /// Stop listening
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        
        DispatchQueue.main.async { [weak self] in
            self?.conversationState.isListening = false
        }
    }
    
    /// Process text input manually
    func processTextInput(_ text: String) {
        guard !text.isEmpty else { return }
        
        // Add to conversation history
        let userMessage = ChatMessage(content: text, isUser: true)
        
        DispatchQueue.main.async { [weak self] in
            self?.conversationState.messages.append(userMessage)
            self?.conversationState.currentMessage = text
            self?.conversationState.isProcessing = true
        }
        
        Task {
            await processInput(text)
        }
    }
    
    /// Set locations from navigation manager
    func setLocations(source: String?, destination: String?) {
        sourceLocation = source
        destinationLocation = destination
    }
    
    /// Set route data
    func setRouteData(_ data: String) {
        routeData = data
        DispatchQueue.main.async { [weak self] in
            self?.conversationState.hasRouteData = true
        }
    }
    
    // MARK: - Private Methods
    
    private func setupSpeechRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }
    
    private func updateSpeechRecognizerLocale() {
        let locale = languageManager?.getCurrentLocale() ?? Locale(identifier: "en-US")
        speechRecognizer = SFSpeechRecognizer(locale: locale)
    }
    
    private func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("ConversationManager: Speech recognition authorized")
                case .denied, .restricted, .notDetermined:
                    self?.handleError("Speech recognition not available. You can still type messages.")
                @unknown default:
                    break
                }
            }
        }
    }
    
    private func performStartListening() {
        // Stop any existing recognition
        stopListening()
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            handleError("Could not configure audio session: \(error.localizedDescription)")
            return
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            handleError("Could not create recognition request")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                
                DispatchQueue.main.async {
                    self.conversationState.currentSpeechText = transcription
                }
                
                if result.isFinal {
                    self.stopListening()
                    self.processTextInput(transcription)
                }
            }
            
            if let error = error {
                print("ConversationManager: Recognition error: \(error)")
                self.stopListening()
            }
        }
        
        // Configure audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        // Start audio engine
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            
            DispatchQueue.main.async { [weak self] in
                self?.conversationState.isListening = true
            }
            
            playFeedbackBeep(type: "start")
            
            // Announce listening
            let message = languageManager?.getString("Listening") ?? "Listening"
            ttsManager?.speakPriority(message)
            
            print("ConversationManager: Started listening")
        } catch {
            handleError("Could not start audio engine: \(error.localizedDescription)")
        }
    }
    
    private func processInput(_ text: String) async {
        // Translate to English if needed
        let englishInput: String
        if languageManager?.isFrench() == true {
            englishInput = await languageManager?.translateToEnglish(text) ?? text
        } else {
            englishInput = text
        }
        
        // Get GPT response
        let gptResponse = await askGemini(englishInput)
        await handleGeminiResponse(gptResponse)
    }
    
    /// Send request to Gemini API using the EXISTING GeminiService.shared
    private func askGemini(_ input: String) async -> String {
        let systemPrompt = buildConversationSystemPrompt()
        
        do {
            // Use EXISTING GeminiService.shared.sendPrompt method
            let response = try await GeminiService.shared.sendPrompt(
                input,
                systemPrompt: systemPrompt
            )
            return response
        } catch {
            print("ConversationManager: Gemini request failed: \(error)")
            
            // Provide helpful error messages
            if let geminiError = error as? GeminiError {
                switch geminiError {
                case .missingAPIKey:
                    return "AI features require an API key. Please add your Gemini API key in the app settings."
                case .invalidURL:
                    return "There was a configuration error. Please try again."
                case .invalidResponse, .decodingError:
                    return "I received an unexpected response. Please try again."
                case .httpError(let code):
                    return "Server error (\(code)). Please try again later."
                case .apiError(let message):
                    return "AI service error: \(message)"
                }
            }
            
            return "I'm having trouble connecting to the AI service. Please check your network connection and try again."
        }
    }
    
    private func handleGeminiResponse(_ response: String) async {
        // Translate if needed
        let translatedResponse: String
        if languageManager?.isFrench() == true {
            translatedResponse = await languageManager?.translateFromEnglish(response) ?? response
        } else {
            translatedResponse = response
        }
        
        await MainActor.run {
            // Add to history
            let assistantMessage = ChatMessage(content: translatedResponse, isUser: false)
            conversationState.messages.append(assistantMessage)
            conversationState.gptResponse = translatedResponse
            conversationState.isProcessing = false
        }
        
        // Speak response
        ttsManager?.speakPriority(translatedResponse)
        playFeedbackBeep(type: "end")
    }
    
    private func handleError(_ message: String) {
        print("ConversationManager: Error - \(message)")
        
        DispatchQueue.main.async { [weak self] in
            self?.conversationState.errorMessage = message
            self?.conversationState.isProcessing = false
            self?.conversationState.isListening = false
        }
        
        ttsManager?.speak(message)
    }
    
    private func buildConversationSystemPrompt() -> String {
        var prompt = """
        You are a helpful indoor navigation assistant.
        Keep responses concise and focused on navigation.
        Respond in 1-2 sentences maximum for simple queries.
        """
        
        if let route = routeData {
            prompt += "\n\nCurrent route information:\n\(route)"
        }
        
        if let source = sourceLocation {
            prompt += "\nUser is starting from: \(source)"
        }
        
        if let destination = destinationLocation {
            prompt += "\nUser is going to: \(destination)"
        }
        
        return prompt
    }
    
    private func playFeedbackBeep(type: String) {
        let systemSoundID: SystemSoundID = type == "start" ? 1113 : 1114
        AudioServicesPlaySystemSound(systemSoundID)
    }
}
