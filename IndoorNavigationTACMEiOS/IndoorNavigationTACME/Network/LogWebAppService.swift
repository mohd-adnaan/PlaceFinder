//
//  LogWebAppService.swift
//  IndoorNavigationTACME
//

import Foundation

private final class LogWebAppRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let fromHost = response.url?.host
        let toHost = request.url?.host

        if fromHost == "script.google.com", toHost == "script.googleusercontent.com" {
            completionHandler(nil)
            return
        }

        completionHandler(request)
    }
}

actor LogWebAppService {

    static let shared = LogWebAppService()

    private let endpointURL: URL?
    private let session: URLSession
    private let redirectDelegate = LogWebAppRedirectDelegate()
    private let formatter: ISO8601DateFormatter

    private init() {
        if let urlString = Bundle.main.object(forInfoDictionaryKey: "LOG_WEB_APP_URL") as? String,
           !urlString.isEmpty,
           let url = URL(string: urlString) {
            endpointURL = url
        } else {
            endpointURL = nil
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration, delegate: redirectDelegate, delegateQueue: nil)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter = iso
    }

    func postLog(level: String, message: String, meta: [String: Any]) async -> Bool {
        guard let endpointURL else {
            DebugLogger.shared.error(.export, "Log upload URL missing")
            return false
        }

        let payload: [String: Any] = [
            "timestamp": formatter.string(from: Date()),
            "level": level,
            "message": message,
            "meta": meta
        ]

        guard JSONSerialization.isValidJSONObject(payload) else {
            DebugLogger.shared.error(.export, "Log upload payload invalid")
            return false
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                DebugLogger.shared.error(.export, "Log upload failed: invalid response")
                return false
            }

            if (200...299).contains(httpResponse.statusCode) {
                DebugLogger.shared.log(.export, .success, "Log upload OK")
                return true
            }

            if httpResponse.statusCode == 302 || httpResponse.statusCode == 303 {
                DebugLogger.shared.log(.export, .success, "Log upload OK (redirected)")
                return true
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                DebugLogger.shared.error(.export, "Log upload failed: HTTP \(httpResponse.statusCode)", detail: body)
                return false
            }

            return false
        } catch {
            DebugLogger.shared.error(.export, "Log upload failed: \(error.localizedDescription)")
            return false
        }
    }
}
