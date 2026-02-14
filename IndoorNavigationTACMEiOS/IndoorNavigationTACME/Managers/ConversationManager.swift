//
//  ConversationManager.swift
//  IndoorNavigationTACME
//
//

import Foundation
import Speech
import AVFoundation
import Combine
import UIKit

class ConversationManager: ObservableObject {
    
    @Published var conversationState = ConversationState()
    
    private var ttsManager: TTSManager?
    private var languageManager: LanguageManager?
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private var sourceLocation: String?
    private var destinationLocation: String?
    private var routeData: String?
    private var conversationContext: [String] = []
    private var feedbackGenerator: UIImpactFeedbackGenerator?
    
    init() {
        feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        print("ConversationManager: Initialized")
    }
    
    func configure(ttsManager: TTSManager, languageManager: LanguageManager) {
        self.ttsManager = ttsManager
        self.languageManager = languageManager
        setupSpeechRecognizer()
        print("ConversationManager: Configured with dependencies")
    }
    
    // MARK: - Public Methods
    
    func startConversationMode() {
        conversationState.isActive = true
        let message = "Conversation mode activated. How can I help you navigate?"
        conversationState.currentMessage = message
        conversationState.errorMessage = nil
        
        ttsManager?.speakPriority(message)
        print("ConversationManager: Starting conversation mode")
        
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("ConversationManager: Speech recognition authorized")
                case .denied:
                    self?.conversationState.errorMessage = "Speech recognition denied"
                case .restricted:
                    self?.conversationState.errorMessage = "Speech recognition restricted"
                case .notDetermined:
                    self?.conversationState.errorMessage = "Speech recognition not determined"
                @unknown default:
                    break
                }
            }
        }
    }
    
    func stopConversationMode() {
        print("ConversationManager: Stopping conversation mode")
        stopListening()
        conversationState = ConversationState()
        sourceLocation = nil
        destinationLocation = nil
        routeData = nil
        conversationContext.removeAll()
        ttsManager?.speakPriority("Conversation mode deactivated")
    }
    
    func startListening() {
        guard conversationState.isActive else {
            print("ConversationManager: Cannot listen - not active")
            return
        }
        
        // FIX: Wait for TTS to finish - accessing audio while TTS speaks causes 0Hz format
        if ttsManager?.ttsState.isSpeaking == true {
            print("ConversationManager: TTS still speaking, delaying listen...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.performStartListening()
            }
        } else {
            performStartListening()
        }
    }
    
    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        DispatchQueue.main.async { [weak self] in
            self?.conversationState.isListening = false
        }
    }
    
    func processTextInput(_ text: String) {
        guard conversationState.isActive, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        print("ConversationManager: Processing: \(text)")
        
        // ChatMessage uses (content:isUser:) - NOT (role:content:timestamp:)
        let userMessage = ChatMessage(content: text, isUser: true)
        
        DispatchQueue.main.async { [weak self] in
            self?.conversationState.messages.append(userMessage)
            self?.conversationState.isProcessing = true
        }
        
        conversationContext.append("User: \(text)")
        
        Task {
            await processInput(text)
        }
    }
    
    func setNavigationContext(source: String, destination: String) {
        sourceLocation = source
        destinationLocation = destination
    }
    
    func setRouteData(_ data: String) {
        routeData = data
        conversationState.hasRouteData = true
    }
    
    // MARK: - Private: Speech Recognition
    
    private func setupSpeechRecognizer() {
        let locale = languageManager?.getCurrentLocale() ?? Locale(identifier: "en-US")
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        
        guard speechRecognizer?.isAvailable == true else {
            print("ConversationManager: Speech recognizer not available")
            return
        }
        print("ConversationManager: Speech recognizer ready for \(locale.identifier)")
    }
    
    private func performStartListening() {
        recognitionTask?.cancel()
        recognitionTask = nil
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // Configure audio session BEFORE reading input format
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("ConversationManager: Audio session error: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.conversationState.errorMessage = "Microphone setup failed"
            }
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest,
              let speechRecognizer = speechRecognizer else {
            print("ConversationManager: Recognizer not available")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            var isFinal = false
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                isFinal = result.isFinal
                
                DispatchQueue.main.async {
                    self?.conversationState.currentSpeechText = text
                }
                
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
        
        // CRITICAL FIX: Validate format before installTap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            print("ConversationManager: ⚠️ Invalid audio format: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount)ch")
            print("  TTS likely still holding audio session. Retrying in 1s...")
            
            recognitionRequest.endAudio()
            self.recognitionRequest = nil
            recognitionTask?.cancel()
            self.recognitionTask = nil
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.performStartListening()
            }
            return
        }
        
        print("ConversationManager: Audio format OK: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount)ch")
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            DispatchQueue.main.async { [weak self] in
                self?.conversationState.isListening = true
            }
            playFeedbackBeep(type: "start")
            print("ConversationManager: Listening started")
        } catch {
            print("ConversationManager: Audio engine start failed: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.conversationState.errorMessage = "Failed to start listening"
                self?.conversationState.isListening = false
            }
        }
    }
    
    // MARK: - Private: AI Processing
    
    private func processInput(_ text: String) async {
        let englishInput: String
        if languageManager?.isFrench() == true {
            englishInput = await languageManager?.translateToEnglish(text) ?? text
        } else {
            englishInput = text
        }
        
        do {
            let locationIntent = await extractLocationsWithGPT(englishInput)
            
            if locationIntent.isNewRouteRequest {
                if let source = locationIntent.source { sourceLocation = source }
                if let destination = locationIntent.destination { destinationLocation = destination }
                
                if let source = sourceLocation, let dest = destinationLocation {
                    // CRITICAL FIX: Fetch route data from server with conversationMode=true
                    // This gives us detailed directions, landmarks, distances
                    await fetchRouteDataAndRespond(source: source, destination: dest, userInput: englishInput)
                    return
                }
            }
            
            if locationIntent.needsClarification {
                let msg: String
                if sourceLocation == nil {
                    msg = "Where are you starting from?"
                } else if destinationLocation == nil {
                    msg = "Where would you like to go?"
                } else {
                    msg = "Could you please provide more details?"
                }
                await handleGPTResponse(locationIntent.clarificationMessage ?? msg)
                return
            }
            
            if conversationState.hasRouteData && locationIntent.isQuestionAboutRoute {
                await processWithGPT(englishInput)
                return
            }
            
            await processWithGPT(englishInput)
            
        } catch {
            await MainActor.run {
                conversationState.isProcessing = false
                conversationState.errorMessage = "Error: \(error.localizedDescription)"
            }
        }
    }
    
    /// Fetch route data from server in conversation mode (MATCHING ANDROID)
    private func fetchRouteDataAndRespond(source: String, destination: String, userInput: String) async {
        do {
            print("ConversationManager: Fetching route \(source) → \(destination) in conversation mode")
            
            let request = InitializeRequest(
                //action: "initialize",
                source: source,
                destination: destination,
                useClockDirections: true,
                useLandmarks: true,
                conversationMode: true
            )
            
            let response = try await NavigationAPIService.shared.initialize(request: request)
            
            if response.status == "success" {
                // Extract conversation data (detailed directions with landmarks)
                if response.conversationMode == true, let convData = response.conversationData {
                    // Convert to JSON string for context
                    if let jsonData = try? JSONSerialization.data(withJSONObject: convData.value, options: []),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        routeData = jsonString
                        print("ConversationManager: Route data received (\(jsonString.count) chars)")
                    }
                } else {
                    routeData = response.message ?? response.instructions
                }
                
                await MainActor.run {
                    conversationState.hasRouteData = true
                }
                
                conversationContext.append("User requested route from \(source) to \(destination)")
                
                // Now process with Gemini to generate a natural language response
                await processWithGPT(userInput)
                
            } else {
                await handleGPTResponse("I couldn't find a route from \(source) to \(destination). Please verify the location names.")
            }
            
        } catch {
            print("ConversationManager: Route fetch error: \(error)")
            await handleGPTResponse("I couldn't connect to the navigation server. Error: \(error.localizedDescription)")
        }
    }
    
    private func extractLocationsWithGPT(_ userInput: String) async -> LocationIntent {
        let systemPrompt = """
        You are a navigation assistant. Analyze user input and extract navigation info.
        
        Context:
        - Known source: \(sourceLocation ?? "none")
        - Known destination: \(destinationLocation ?? "none")
        
        Location normalization: remove spaces, lowercase. "female restroom" → "femalerestroom"
        
        Respond with ONLY JSON:
        {"is_new_route_request":false,"is_question_about_route":false,"needs_clarification":false,"source":null,"destination":null,"clarification_message":null}
        """
        
        do {
            let response = try await GeminiService.shared.sendPrompt(
                "User says: \"\(userInput)\"\n\nExtract navigation intent.",
                systemPrompt: systemPrompt
            )
            return parseLocationIntent(response)
        } catch {
            print("ConversationManager: Location extraction error: \(error)")
            return LocationIntent()
        }
    }
    
    private func processWithGPT(_ input: String) async {
        // Build system prompt matching Android's buildNavigationGPTRequest
        var systemPrompt = """
        You are a helpful indoor navigation assistant providing clear directions.
        Keep responses brief and conversational (under 100 words).
        
        When given route data:
        1. Combine consecutive similar actions (add up steps: 2+5+3 = 10 steps)
        2. Only mention major turns and landmarks
        3. Keep it conversational and easy to remember
        
        Example good summary: "Walk straight for 15 steps, turn right at the water fountain, continue for 8 steps, and the destination is on your left."
        """
        
        if let source = sourceLocation, let dest = destinationLocation {
            systemPrompt += "\nCurrent route: \(source) → \(dest)"
        }
        
        if let routeData = routeData {
            // Truncate if too long to avoid token limits
            let truncated = routeData.count > 3000 ? String(routeData.prefix(3000)) + "..." : routeData
            systemPrompt += "\n\nRoute data (with landmarks and directions):\n\(truncated)"
        }
        
        do {
            let response = try await GeminiService.shared.sendPrompt(input, systemPrompt: systemPrompt)
            await handleGPTResponse(response)
        } catch {
            await MainActor.run {
                conversationState.isProcessing = false
                conversationState.errorMessage = "AI error: \(error.localizedDescription)"
            }
        }
    }
    
    private func handleGPTResponse(_ response: String) async {
        let translatedResponse: String
        if languageManager?.isFrench() == true {
            translatedResponse = await languageManager?.translateFromEnglish(response) ?? response
        } else {
            translatedResponse = response
        }
        
        // ChatMessage uses (content:isUser:) - timestamp has default value
        let assistantMessage = ChatMessage(content: translatedResponse, isUser: false)
        conversationContext.append("Assistant: \(response)")
        
        await MainActor.run {
            conversationState.messages.append(assistantMessage)
            conversationState.gptResponse = translatedResponse
            conversationState.isProcessing = false
        }
        
        ttsManager?.speak(translatedResponse, force: true)
    }
    
    private func parseLocationIntent(_ response: String) -> LocationIntent {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("ConversationManager: Failed to parse intent JSON")
            return LocationIntent()
        }
        
        return LocationIntent(
            isNewRouteRequest: json["is_new_route_request"] as? Bool ?? false,
            isQuestionAboutRoute: json["is_question_about_route"] as? Bool ?? false,
            needsClarification: json["needs_clarification"] as? Bool ?? false,
            source: json["source"] as? String,
            destination: json["destination"] as? String,
            clarificationMessage: json["clarification_message"] as? String
        )
    }
    
    // MARK: - Audio Feedback
    
    private func playFeedbackBeep(type: String) {
        feedbackGenerator?.impactOccurred()
        switch type {
        case "start": AudioServicesPlaySystemSound(1113)
        case "end": AudioServicesPlaySystemSound(1114)
        case "error": AudioServicesPlaySystemSound(1053)
        default: break
        }
    }
    
    func cleanup() {
        stopListening()
        conversationContext.removeAll()
    }
}
