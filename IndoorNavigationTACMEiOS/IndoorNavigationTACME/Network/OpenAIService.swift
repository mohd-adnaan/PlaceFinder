//
//  OpenAIService.swift
//  IndoorNavigationTACME
//
//  Created by Mohammad Adnaan on 2026-02-23.
//

import Foundation

// MARK: - Errors

enum OpenAIError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case httpError(statusCode: Int, body: String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:      return "OpenAI API key not found in Info.plist"
        case .invalidURL:         return "Invalid OpenAI URL"
        case .httpError(let c, let b): return "OpenAI HTTP \(c): \(b)"
        case .decodingError:      return "Failed to decode OpenAI response"
        }
    }
}

// MARK: - Service

final class OpenAIService {

    static let shared = OpenAIService()

    private let apiKey: String
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    private let model   = "gpt-4o-mini"

    private init() {
        // Accept both common key names used in Info.plist
        let dict = Bundle.main.infoDictionary ?? [:]
        if let key = dict["OPENAI_API_KEY"] as? String, !key.isEmpty {
            apiKey = key
        } else if let key = dict["OPEN_API_KEY"] as? String, !key.isEmpty {
            apiKey = key
        } else if let key = dict["OpenAIAPIKey"] as? String, !key.isEmpty {
            apiKey = key
        } else {
            apiKey = ""
            print("⚠️  OpenAIService: API key not found in Info.plist. Add OPENAI_API_KEY.")
        }
    }

    // MARK: - Public API

    /// Send a chat conversation and return the assistant reply.
    /// - Parameters:
    ///   - messages: Array of `["role": "user"|"assistant"|"system", "content": "…"]`
    ///   - maxTokens: Upper bound on generated tokens (default 600).
    func chatCompletion(messages: [[String: String]],
                        maxTokens: Int = 600) async throws -> String {
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }
        guard let url = URL(string: endpoint) else { throw OpenAIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model":      model,
            "messages":   messages,
            "max_tokens": maxTokens,
            "temperature": 0.7
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)

        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "—"
            throw OpenAIError.httpError(statusCode: httpResp.statusCode, body: body)
        }

        guard
            let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first   = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw OpenAIError.decodingError }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Convenience: one system prompt + one user message.
    func sendPrompt(_ userText: String,
                    systemPrompt: String? = nil,
                    maxTokens: Int = 600) async throws -> String {
        var messages: [[String: String]] = []
        if let sys = systemPrompt {
            messages.append(["role": "system", "content": sys])
        }
        messages.append(["role": "user", "content": userText])
        return try await chatCompletion(messages: messages, maxTokens: maxTokens)
    }
}
