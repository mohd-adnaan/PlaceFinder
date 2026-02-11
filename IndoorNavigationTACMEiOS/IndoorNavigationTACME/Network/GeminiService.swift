//
//  GeminiService.swift
//  IndoorNavigationTACME
//

import Foundation

/// Service for communicating with Google Gemini API
actor GeminiService {
    
    // MARK: - Properties
    
    // FIXED: Use v1beta which supports gemini-2.0-flash
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private let session: URLSession
    private var apiKey: String?
    
    // FIXED: Default model updated from "gemini-1.5-flash" to "gemini-2.0-flash"
    static let defaultModel = "gemini-2.0-flash"
    
    // MARK: - Singleton
    
    static let shared = GeminiService()
    
    // MARK: - Initialization
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: configuration)
        
        // Load API key from environment or configuration
        if let key = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String,
           !key.isEmpty, !key.contains("$(") {
            self.apiKey = key
            print("GeminiService: API key loaded from Info.plist")
        } else if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty {
            self.apiKey = key
            print("GeminiService: API key loaded from environment")
        } else if let key = UserDefaults.standard.string(forKey: "GEMINI_API_KEY"), !key.isEmpty {
            self.apiKey = key
            print("GeminiService: API key loaded from UserDefaults")
        } else {
            print("⚠️ GeminiService: Gemini API key not found! AI features will not work.")
            print("   Add GEMINI_API_KEY to Info.plist or environment variables")
        }
    }
    
    // MARK: - Public Methods
    
    /// Set API key programmatically
    func setAPIKey(_ key: String) {
        self.apiKey = key
        print("GeminiService: API key set programmatically")
    }
    
    /// Check if API is configured
    func isConfigured() -> Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }
    
    /// Send a generate content request to Gemini
    func generateContent(request: GeminiRequest) async throws -> GeminiResponse {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw GeminiError.missingAPIKey
        }
        
        // FIXED: Use gemini-2.0-flash as default instead of gemini-1.5-flash
        let model = request.model ?? GeminiService.defaultModel
        guard let url = URL(string: "\(baseURL)/\(model):generateContent?key=\(apiKey)") else {
            throw GeminiError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build request body
        var body: [String: Any] = [:]
        
        // Convert messages to Gemini format
        var contents: [[String: Any]] = []
        var systemInstruction: String? = nil
        
        for message in request.messages {
            if message.role == "system" {
                systemInstruction = message.content
            } else {
                let geminiRole = message.role == "assistant" ? "model" : "user"
                contents.append([
                    "role": geminiRole,
                    "parts": [["text": message.content]]
                ])
            }
        }
        
        body["contents"] = contents
        
        // Add system instruction if present
        if let systemInstruction = systemInstruction {
            body["systemInstruction"] = [
                "parts": [["text": systemInstruction]]
            ]
        }
        
        // Generation config
        body["generationConfig"] = [
            "temperature": request.temperature,
            "maxOutputTokens": request.maxTokens,
            "topP": 0.95,
            "topK": 40
        ]
        
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        #if DEBUG
        print("Gemini Request to model '\(model)': \(request.messages.last?.content.prefix(100) ?? "empty")")
        #endif
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorString = String(data: data, encoding: .utf8) {
                print("Gemini Error Response (\(httpResponse.statusCode)): \(errorString)")
                
                // Try to parse error message
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw GeminiError.apiError(message: message)
                }
            }
            throw GeminiError.httpError(statusCode: httpResponse.statusCode)
        }
        
        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.decodingError
        }
        
        guard let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiError.decodingError
        }
        
        return GeminiResponse(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
    
    /// Simple helper for sending a prompt and getting a response
    func sendPrompt(_ prompt: String, systemPrompt: String? = nil) async throws -> String {
        var messages: [GeminiMessage] = []
        
        if let systemPrompt = systemPrompt {
            messages.append(GeminiMessage(role: "system", content: systemPrompt))
        }
        messages.append(GeminiMessage(role: "user", content: prompt))
        
        let request = GeminiRequest(
            messages: messages,
            maxTokens: 1000,
            temperature: 0.7
        )
        
        let response = try await generateContent(request: request)
        return response.text
    }
    
    /// Chat completion compatible method
    func chatCompletion(messages: [GeminiMessage], maxTokens: Int = 1000, temperature: Double = 0.7) async throws -> String {
        let request = GeminiRequest(
            messages: messages,
            maxTokens: maxTokens,
            temperature: temperature
        )
        
        let response = try await generateContent(request: request)
        return response.text
    }
}

// MARK: - Request/Response Models

struct GeminiRequest {
    let model: String?
    let messages: [GeminiMessage]
    let maxTokens: Int
    let temperature: Double
    
    // FIXED: Default model is now gemini-2.0-flash
    init(model: String? = GeminiService.defaultModel, messages: [GeminiMessage], maxTokens: Int = 1000, temperature: Double = 0.7) {
        self.model = model
        self.messages = messages
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

struct GeminiMessage {
    let role: String  // "system", "user", or "assistant"
    let content: String
}

struct GeminiResponse {
    let text: String
}

// MARK: - Errors

enum GeminiError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case apiError(message: String)
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API key not configured. Add GEMINI_API_KEY to Info.plist."
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from Gemini"
        case .httpError(let statusCode):
            return "Gemini HTTP error: \(statusCode)"
        case .apiError(let message):
            return "AI service error: \(message)"
        case .decodingError:
            return "Failed to decode Gemini response"
        }
    }
}
