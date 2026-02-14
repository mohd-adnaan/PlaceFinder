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
        // FIXED: Point to actual backend server
        self.baseURL = URL(string: "https://indoornavigationtacme-production.up.railway.app")!
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
