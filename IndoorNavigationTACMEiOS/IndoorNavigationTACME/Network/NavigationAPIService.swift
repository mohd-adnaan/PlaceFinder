//
//  NavigationAPIService.swift
//  IndoorNavigationTACME
//

import Foundation

actor NavigationAPIService {
    
    private let baseURL: URL
    private let session: URLSession
    private var sessionId: String
    
    static let shared = NavigationAPIService()
    
    private init() {
        self.baseURL = URL(string: "https://cybersight.cim.mcgill.ca/navigation")!
        self.sessionId = "ios_session_\(Int(Date().timeIntervalSince1970 * 1000))"
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)
    }
    
    func initialize(request: InitializeRequest) async throws -> NavigationResponse {
        return try await performRequest(path: "wayfinder", body: request)
    }
    
    func updatePosition(request: UpdateRequest) async throws -> NavigationResponse {
        return try await performRequest(path: "wayfinder", body: request)
    }
    
    func resetSession() {
        sessionId = "ios_session_\(Int(Date().timeIntervalSince1970 * 1000))"
    }

    func queryConversation(
        userText: String,
        source: String?,
        destination: String?,
        routeData: String?
    ) async throws -> NavigationResponse {
        var attempts: [[String: Any]] = []

        var payloadA: [String: Any] = [
            "action": "conversation",
            "conversationMode": true,
            "source": source ?? "",
            "destination": destination ?? "",
            "conversationData": [
                "query": userText
            ]
        ]
        
        if let routeData, !routeData.isEmpty {
            payloadA["conversationData"] = [
                "query": userText,
                "routeData": String(routeData.prefix(1200))
            ]
        }
        attempts.append(payloadA)

        // Some deployments only accept initialize/update shapes.
        if let source, !source.isEmpty,
           let destination, !destination.isEmpty {
            var payloadB: [String: Any] = [
                "action": "initialize",
                "source": source,
                "destination": destination,
                "conversationMode": true,
                "useClockDirections": true,
                "useLandmarks": true,
                "conversationData": [
                    "query": userText
                ]
            ]
            if let routeData, !routeData.isEmpty {
                payloadB["conversationData"] = [
                    "query": userText,
                    "routeData": String(routeData.prefix(1200))
                ]
            }
            attempts.append(payloadB)
        }

        // Last fallback: lightweight update-like body with placeholder pose.
        attempts.append([
            "action": "update",
            "currentX": 0,
            "currentY": 0,
            "currentBearing": 0,
            "conversationMode": true,
            "conversationData": [
                "query": userText
            ]
        ])

        var lastError: Error?
        for body in attempts {
            do {
                return try await performJSONObjectRequest(path: "wayfinder", body: body)
            } catch {
                lastError = error
                // Try the next shape if server rejects the current schema.
                continue
            }
        }

        throw lastError ?? NavigationAPIError.invalidResponse
    }
    
    private func performRequest<T: Encodable>(path: String, body: T) async throws -> NavigationResponse {
        // Build URL with session_id as query parameter (matching API docs)
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "session_id", value: sessionId)]
        
        guard let url = components.url else {
            throw NavigationAPIError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Also send as header for Android compatibility
        request.setValue(sessionId, forHTTPHeaderField: "Session-ID")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)
        
        #if DEBUG
        if let bodyData = request.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            print("NavigationAPI POST \(url)")
            print("NavigationAPI Body: \(bodyString)")
        }
        #endif
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NavigationAPIError.invalidResponse
        }
        
        #if DEBUG
        if let responseString = String(data: data, encoding: .utf8) {
            // Truncate long responses for readability
            let truncated = responseString.count > 500 ? String(responseString.prefix(500)) + "..." : responseString
            print("NavigationAPI Response (\(httpResponse.statusCode)): \(truncated)")
        }
        #endif
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NavigationAPIError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(NavigationResponse.self, from: data)
        } catch {
            print("NavigationAPI Decode Error: \(error)")
            // Print the raw response to help debug
            if let raw = String(data: data, encoding: .utf8) {
                print("NavigationAPI Raw: \(raw)")
            }
            throw NavigationAPIError.decodingError(error)
        }
    }

    private func performJSONObjectRequest(path: String, body: [String: Any]) async throws -> NavigationResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "session_id", value: sessionId)]

        guard let url = components.url else {
            throw NavigationAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(sessionId, forHTTPHeaderField: "Session-ID")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        #if DEBUG
        if let bodyData = request.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            print("NavigationAPI POST \(url)")
            print("NavigationAPI Body: \(bodyString)")
        }
        #endif

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NavigationAPIError.invalidResponse
        }

        #if DEBUG
        if let responseString = String(data: data, encoding: .utf8) {
            let truncated = responseString.count > 500 ? String(responseString.prefix(500)) + "..." : responseString
            print("NavigationAPI Response (\(httpResponse.statusCode)): \(truncated)")
        }
        #endif

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NavigationAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(NavigationResponse.self, from: data)
        } catch {
            print("NavigationAPI Decode Error: \(error)")
            if let raw = String(data: data, encoding: .utf8) {
                print("NavigationAPI Raw: \(raw)")
            }
            throw NavigationAPIError.decodingError(error)
        }
    }
}

enum NavigationAPIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
