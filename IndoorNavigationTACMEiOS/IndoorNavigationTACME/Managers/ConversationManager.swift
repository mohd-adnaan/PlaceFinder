//
//  ConversationManager.swift
//  IndoorNavigationTACME
//
//  Manages AI conversation-based navigation
//

import Foundation
import Speech
import AVFoundation
import Combine
import UIKit

/// Manages conversation-based navigation with GPT integration
class ConversationManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var conversationState = ConversationState()
    
    // MARK: - Private Properties
    
    private var ttsManager: TTSManager?
    private var languageManager: LanguageManager?
    
    // Speech recognition
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // Location tracking
    private var sourceLocation: String?
    private var destinationLocation: String?
    private var routeData: String?
    
    // Audio feedback
    private var feedbackGenerator: UIImpactFeedbackGenerator?
    
    // MARK: - Initialization
    
    init() {
        feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        print("ConversationManager: Initialized")
    }
    
    // MARK: - Configuration
    
    /// Configure manager dependencies
    func configure(ttsManager: TTSManager, languageManager: LanguageManager) {
        self.ttsManager = ttsManager
        self.languageManager = languageManager
        setupSpeechRecognizer()
        print("ConversationManager: Dependencies configured")
    }
    
    // MARK: - Public Methods
    
    /// Start conversation mode
    func startConversationMode() {
        conversationState.isActive = true
        let message = languageManager?.getString("listening") ?? "Listening"
        ttsManager?.speakPriority(message)
        print("ConversationManager: Conversation mode started")
    }
    
    /// Stop conversation mode
    func stopConversationMode() {
        stopListening()
        conversationState = ConversationState()
        sourceLocation = nil
        destinationLocation = nil
        routeData = nil
        print("ConversationManager: Conversation mode stopped")
    }
    
    /// Start listening for voice input
    func startListening() {
        guard conversationState.isActive else { return }
        
        // Check authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.performStartListening()
                case .denied, .restricted, .notDetermined:
                    self?.conversationState.errorMessage = "Speech recognition not authorized"
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
        
        conversationState.isListening = false
    }
    
    /// Process text input manually
    func processTextInput(_ text: String) {
        guard !text.isEmpty else { return }
        
        // Add to conversation history
        let userMessage = ChatMessage(content: text, isUser: true)
        conversationState.messages.append(userMessage)
        conversationState.currentMessage = text
        conversationState.isProcessing = true
        
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
        conversationState.hasRouteData = true
    }
    
    // MARK: - Private Methods
    
    private func setupSpeechRecognizer() {
        let locale = languageManager?.getCurrentLocale() ?? Locale(identifier: "en-US")
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        
        guard speechRecognizer?.isAvailable == true else {
            print("ConversationManager: Speech recognizer not available")
            return
        }
        
        print("ConversationManager: Speech recognizer configured for \(locale.identifier)")
    }
    
    private func performStartListening() {
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("ConversationManager: Audio session error: \(error)")
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest,
              let speechRecognizer = speechRecognizer else {
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Configure on-device recognition if available
        if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            var isFinal = false
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                isFinal = result.isFinal
                
                if isFinal {
                    DispatchQueue.main.async {
                        self?.stopListening()
                        self?.processTextInput(text)
                    }
                }
            }
            
            if error != nil || isFinal {
                self?.audioEngine.stop()
                self?.audioEngine.inputNode.removeTap(onBus: 0)
                self?.recognitionRequest = nil
                self?.recognitionTask = nil
                
                DispatchQueue.main.async {
                    self?.conversationState.isListening = false
                }
            }
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            conversationState.isListening = true
            playFeedbackBeep(type: "start")
            print("ConversationManager: Started listening")
        } catch {
            print("ConversationManager: Could not start audio engine: \(error)")
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
        
        do {
            // Extract location intent
            let locationIntent = await extractLocationsWithGPT(englishInput)
            
            // Handle new route request
            if locationIntent.isNewRouteRequest {
                if let source = locationIntent.source {
                    sourceLocation = source
                }
                if let destination = locationIntent.destination {
                    destinationLocation = destination
                }
                
                // Check if we have both locations
                if sourceLocation != nil && destinationLocation != nil {
                    // Ready to start navigation
                    let response = "Starting navigation from \(sourceLocation!) to \(destinationLocation!)."
                    await handleGPTResponse(response)
                    return
                }
            }
            
            // Handle clarification needed
            if locationIntent.needsClarification {
                let clarificationMsg: String
                if sourceLocation == nil {
                    clarificationMsg = "Where are you starting from?"
                } else if destinationLocation == nil {
                    clarificationMsg = "Where would you like to go?"
                } else {
                    clarificationMsg = "Could you please provide more details?"
                }
                await handleGPTResponse(locationIntent.clarificationMessage ?? clarificationMsg)
                return
            }
            
            // Question about route
            if conversationState.hasRouteData && locationIntent.isQuestionAboutRoute {
                await processWithGPT(englishInput)
                return
            }
            
            // General conversation
            await processWithGPT(englishInput)
            
        } catch {
            await MainActor.run {
                conversationState.isProcessing = false
                conversationState.errorMessage = "Error: \(error.localizedDescription)"
            }
        }
    }
    
    private func extractLocationsWithGPT(_ userInput: String) async -> LocationIntent {
        let prompt = buildLocationExtractionPrompt(userInput)
        
        do {
            let response = try await GeminiService.shared.sendPrompt(prompt, systemPrompt: locationExtractionSystemPrompt())
            return parseLocationIntent(response)
        } catch {
            print("ConversationManager: Location extraction error: \(error)")
            return LocationIntent()
        }
    }
    
    private func processWithGPT(_ input: String) async {
        let systemPrompt = buildConversationSystemPrompt()
        
        do {
            let response = try await GeminiService.shared.sendPrompt(input, systemPrompt: systemPrompt)
            await handleGPTResponse(response)
        } catch {
            await MainActor.run {
                conversationState.isProcessing = false
                conversationState.errorMessage = "Failed to get response"
            }
        }
    }
    
    private func handleGPTResponse(_ response: String) async {
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
    
    private func buildLocationExtractionPrompt(_ userInput: String) -> String {
        return """
        Analyze this user input for navigation intent:
        "\(userInput)"
        
        Current context:
        - Known source: \(sourceLocation ?? "none")
        - Known destination: \(destinationLocation ?? "none")
        
        Extract and return JSON with:
        - isNewRouteRequest: boolean
        - isQuestionAboutRoute: boolean
        - needsClarification: boolean
        - source: string or null
        - destination: string or null
        - clarificationMessage: string or null
        """
    }
    
    private func locationExtractionSystemPrompt() -> String {
        return """
        You are a location extraction assistant for an indoor navigation system.
        Your job is to analyze user input and extract navigation-related information.
        Return only valid JSON with the requested fields.
        """
    }
    
    private func buildConversationSystemPrompt() -> String {
        var prompt = """
        You are a helpful indoor navigation assistant.
        Keep responses concise and focused on navigation.
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
    
    private func parseLocationIntent(_ response: String) -> LocationIntent {
        // Try to parse JSON response
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return LocationIntent()
        }
        
        return LocationIntent(
            isNewRouteRequest: json["isNewRouteRequest"] as? Bool ?? false,
            isQuestionAboutRoute: json["isQuestionAboutRoute"] as? Bool ?? false,
            needsClarification: json["needsClarification"] as? Bool ?? false,
            source: json["source"] as? String,
            destination: json["destination"] as? String,
            clarificationMessage: json["clarificationMessage"] as? String
        )
    }
    
    private func playFeedbackBeep(type: String) {
        feedbackGenerator?.impactOccurred()
        
        // Play system sound
        let soundId: SystemSoundID = type == "start" ? 1052 : 1054
        AudioServicesPlaySystemSound(soundId)
    }
}
