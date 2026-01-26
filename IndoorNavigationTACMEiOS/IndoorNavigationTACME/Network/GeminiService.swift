//
//  GeminiService.swift
//  IndoorNavigationTACME
//
//  Service for Google Gemini API communication
//

import Foundation

/// Service for communicating with Google Gemini API
actor GeminiService {
    
    // MARK: - Properties
    
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private let session: URLSession
    private var apiKey: String?
    
    // MARK: - Singleton
    
    static let shared = GeminiService()
    
    // MARK: - Initialization
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: configuration)
        
        // Load API key from environment or configuration
        // Try loading from Info.plist
        if let key = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String,
           !key.isEmpty, !key.contains("$(") {
            self.apiKey = key
        } else if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty {
            self.apiKey = key
        } else if let key = UserDefaults.standard.string(forKey: "GEMINI_API_KEY"), !key.isEmpty {
            self.apiKey = key
        } else {
            print("Warning: Gemini API key not found")
        }
    }
    
    // MARK: - Public Methods
    
    /// Set API key
    func setAPIKey(_ key: String) {
        self.apiKey = key
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
        
        let model = request.model ?? "gemini-1.5-flash"
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
        print("Gemini Request: \(request.messages.last?.content.prefix(100) ?? "empty")")
        #endif
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorString = String(data: data, encoding: .utf8) {
                print("Gemini Error Response: \(errorString)")
                
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
    
    /// Chat completion compatible method (for easier migration from OpenAI)
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
    
    init(model: String? = "gemini-1.5-flash", messages: [GeminiMessage], maxTokens: Int = 1000, temperature: Double = 0.7) {
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
            return "Gemini API key not configured"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from Gemini"
        case .httpError(let statusCode):
            return "Gemini HTTP error: \(statusCode)"
        case .apiError(let message):
            return "Gemini API error: \(message)"
        case .decodingError:
            return "Failed to decode Gemini response"
        }
    }
}
