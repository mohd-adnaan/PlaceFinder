//
//  DebugLogger.swift
//  IndoorNavigationTACME
//
//  Created by Mohammad Adnaan on 2026-03-15.
//
//  Centralized logging system that captures API calls, responses, errors,
//  navigation events, and sensor events for debugging and research export.
//

import Foundation
import Combine

// MARK: - Log Entry

struct DebugLogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let category: LogCategory
    let level: LogLevel
    let message: String
    /// Optional detail payload (e.g. full JSON body / response)
    let detail: String?
    
    init(category: LogCategory, level: LogLevel, message: String, detail: String? = nil) {
        self.timestamp = Date()
        self.category = category
        self.level = level
        self.message = message
        self.detail = detail
    }
    
    static func == (lhs: DebugLogEntry, rhs: DebugLogEntry) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum LogCategory: String, CaseIterable {
    case api = "API"
    case navigation = "NAV"
    case sensor = "IMU"
    case conversation = "CHAT"
    case gemini = "AI"
    case tts = "TTS"
    case qr = "QR"
    case system = "SYS"
    case export = "EXPORT"
    
    var emoji: String {
        switch self {
        case .api: return "🌐"
        case .navigation: return "🧭"
        case .sensor: return "📡"
        case .conversation: return "💬"
        case .gemini: return "🤖"
        case .tts: return "🔊"
        case .qr: return "📷"
        case .system: return "⚙️"
        case .export: return "📤"
        }
    }
}

enum LogLevel: String, CaseIterable {
    case info = "INFO"
    case success = "OK"
    case warning = "WARN"
    case error = "ERR"
    case debug = "DBG"
    
    var color: String {
        switch self {
        case .info: return "blue"
        case .success: return "green"
        case .warning: return "orange"
        case .error: return "red"
        case .debug: return "gray"
        }
    }
}

// MARK: - Debug Logger

class DebugLogger: ObservableObject {
    
    static let shared = DebugLogger()
    
    @Published var entries: [DebugLogEntry] = []
    @Published var isEnabled: Bool = true
    
    private let maxEntries = 2000
    private let queue = DispatchQueue(label: "com.tacme.debuglogger", qos: .utility)
    
    private init() {}
    
    // MARK: - Logging Methods
    
    func log(_ category: LogCategory, _ level: LogLevel, _ message: String, detail: String? = nil) {
        guard isEnabled else { return }
        let entry = DebugLogEntry(category: category, level: level, message: message, detail: detail)
        queue.async { [weak self] in
            DispatchQueue.main.async {
                self?.entries.append(entry)
                if let count = self?.entries.count, count > self?.maxEntries ?? 2000 {
                    self?.entries.removeFirst(count - (self?.maxEntries ?? 2000))
                }
            }
        }
        // Also print to console for Xcode debugging
        #if DEBUG
        print("[\(category.rawValue)/\(level.rawValue)] \(message)")
        #endif
    }
    
    // MARK: - Convenience
    
    func apiRequest(_ method: String, url: String, body: String?) {
        log(.api, .info, "\(method) \(url)", detail: body)
    }
    
    func apiResponse(_ statusCode: Int, url: String, body: String?) {
        let level: LogLevel = (200...299).contains(statusCode) ? .success : .error
        log(.api, level, "← \(statusCode) \(url)", detail: body)
    }
    
    func apiError(_ url: String, error: Error) {
        log(.api, .error, "✗ \(url): \(error.localizedDescription)")
    }
    
    func navEvent(_ message: String, detail: String? = nil) {
        log(.navigation, .info, message, detail: detail)
    }
    
    func sensorEvent(_ message: String) {
        log(.sensor, .debug, message)
    }
    
    func conversationEvent(_ message: String, detail: String? = nil) {
        log(.conversation, .info, message, detail: detail)
    }
    
    func geminiEvent(_ message: String, detail: String? = nil) {
        log(.gemini, .info, message, detail: detail)
    }
    
    func error(_ category: LogCategory, _ message: String, detail: String? = nil) {
        log(category, .error, message, detail: detail)
    }
    
    // MARK: - Clear
    
    func clear() {
        DispatchQueue.main.async {
            self.entries.removeAll()
        }
    }
    
    // MARK: - Export
    
    func exportLogsAsText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        
        var output = "=== IndoorNavigationTACME Debug Log ===\n"
        output += "Exported: \(Date())\n"
        output += "Entries: \(entries.count)\n"
        output += "========================================\n\n"
        
        for entry in entries {
            let time = formatter.string(from: entry.timestamp)
            output += "[\(time)] \(entry.category.emoji) \(entry.category.rawValue)/\(entry.level.rawValue): \(entry.message)\n"
            if let detail = entry.detail {
                // Indent detail lines
                let indented = detail.components(separatedBy: "\n").map { "    \($0)" }.joined(separator: "\n")
                output += "\(indented)\n"
            }
        }
        
        return output
    }
    
    /// Filter entries by category
    func entries(for categories: Set<LogCategory>) -> [DebugLogEntry] {
        if categories.isEmpty { return entries }
        return entries.filter { categories.contains($0.category) }
    }
}
