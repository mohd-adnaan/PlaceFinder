//
//  NavigationAPIService.swift
//  IndoorNavigationTACME
//
//  Network service for navigation API communication
//

import Foundation

/// Service for communicating with the navigation backend
actor NavigationAPIService {
    
    // MARK: - Properties
    
    private let baseURL: URL
    private let session: URLSession
    private var sessionId: String
    
    // MARK: - Singleton
    
    static let shared = NavigationAPIService()
    
    // MARK: - Initialization
    
    private init() {
        // Configure base URL - production server
        self.baseURL = URL(string: "https://indoornavigationtacme-production.up.railway.app")!
        self.sessionId = "ios_session_\(Int(Date().timeIntervalSince1970 * 1000))"
        
        // Configure URLSession with timeout settings
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        
        self.session = URLSession(configuration: configuration)
    }
    
    // MARK: - Public Methods
    
    /// Initialize navigation session with source and destination
    func initialize(request: InitializeRequest) async throws -> NavigationResponse {
        let endpoint = baseURL.appendingPathComponent("wayfinder")
        return try await performRequest(endpoint: endpoint, body: request)
    }
    
    /// Update current position and get navigation instructions
    func updatePosition(request: UpdateRequest) async throws -> NavigationResponse {
        let endpoint = baseURL.appendingPathComponent("wayfinder")
        return try await performRequest(endpoint: endpoint, body: request)
    }
    
    /// Reset session ID for new navigation
    func resetSession() {
        sessionId = "ios_session_\(Int(Date().timeIntervalSince1970 * 1000))"
    }
    
    // MARK: - Private Methods
    
    private func performRequest<T: Encodable>(endpoint: URL, body: T) async throws -> NavigationResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionId, forHTTPHeaderField: "Session-ID")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)
        
        #if DEBUG
        if let bodyData = request.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            print("NavigationAPI Request: \(bodyString)")
        }
        #endif
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NavigationAPIError.invalidResponse
        }
        
        #if DEBUG
        if let responseString = String(data: data, encoding: .utf8) {
            print("NavigationAPI Response (\(httpResponse.statusCode)): \(responseString)")
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
            throw NavigationAPIError.decodingError(error)
        }
    }
}

// MARK: - Errors

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
