//
//  TTSManager.swift
//  IndoorNavigationTACME
//
//  Manages text-to-speech for navigation instructions
//

import Foundation
import AVFoundation
import Combine

/// Manages text-to-speech for navigation instructions
class TTSManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var ttsState = TTSState()
    
    // MARK: - Private Properties
    
    private let synthesizer = AVSpeechSynthesizer()
    private var languageManager: LanguageManager?
    
    // Timing configuration
    private var minTimeBetweenRegularInstructions: TimeInterval = 3.0
    private var minTimeBetweenPriorityInstructions: TimeInterval = 1.5
    private var minTimeBetweenCriticalInstructions: TimeInterval = 0.5
    private var minTimeBetweenNeverMissInstructions: TimeInterval = 3.0
    
    // Instruction tracking
    private var lastNormalizedInstruction: String = ""
    private var lastTimedNeverMissInstructionTimes: [String: Date] = [:]
    private var spokenOneTimeInstructions: Set<String> = []
    
    // Speech configuration
    private let speechRate: Float = 0.52 // Slightly faster than default
    private let speechPitch: Float = 1.0
    
    // Keywords for instruction priority
    private let neverMissNoConsecutiveKeywords: Set<String> = [
        "arrived", "reached", "destination", "approaching", "finished"
    ]
    
    private let neverMissTimedKeywords: Set<String> = [
        "turn left", "turn right", "press"
    ]
    
    private let priorityKeywords: Set<String> = [
        "straight", "reversed", "recalibrate", "error", "keep moving",
        "turn completed", "press"
    ]
    
    private let criticalKeywords: Set<String> = [
        "backtrack", "wrong direction", "danger", "keep moving", "stop",
        "error", "turn completed", "make", "turn left", "turn right"
    ]
    
    private let oneTimeKeywords: Set<String> = [
        "reached", "finished", "approaching", "arrived", "destination"
    ]
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        synthesizer.delegate = self
        setupAudioSession()
        ttsState.isReady = true
        print("TTSManager: Initialized")
    }
    
    // MARK: - Public Methods
    
    /// Set the language manager reference
    func setLanguageManager(_ manager: LanguageManager) {
        self.languageManager = manager
        print("TTSManager: Language manager set")
    }
    
    /// Speak the given text with intelligent filtering
    func speak(_ text: String, force: Bool = false) {
        guard ttsState.isReady && ttsState.isEnabled && !text.isEmpty else {
            print("TTSManager: TTS not ready or disabled, skipping: \(text)")
            return
        }
        
        let currentTime = Date()
        
        if !force && !shouldSpeakWithPriority(text, currentTime: currentTime) {
            print("TTSManager: Skipping instruction: \(text)")
            return
        }
        
        performSpeak(text)
    }
    
    /// Speak with explicit priority override
    func speakPriority(_ text: String) {
        guard ttsState.isReady && ttsState.isEnabled else { return }
        
        let normalizedInstruction = normalizeInstruction(text)
        let currentTime = Date()
        
        // Check for never-miss no-consecutive
        if isNeverMissNoConsecutiveInstruction(text) {
            if normalizedInstruction == lastNormalizedInstruction {
                print("TTSManager: Skipping consecutive never-miss: \(text)")
                return
            }
        }
        
        // Check for never-miss timed
        if isNeverMissTimedInstruction(text) {
            if let lastTime = lastTimedNeverMissInstructionTimes[normalizedInstruction] {
                let timeSince = currentTime.timeIntervalSince(lastTime)
                if timeSince < minTimeBetweenNeverMissInstructions {
                    print("TTSManager: Skipping never-miss within window: \(text)")
                    return
                }
            }
            lastTimedNeverMissInstructionTimes[normalizedInstruction] = currentTime
        }
        
        performSpeak(text)
        lastNormalizedInstruction = normalizedInstruction
    }
    
    /// Speak critical instruction that bypasses normal filtering
    func speakCritical(_ text: String) {
        guard ttsState.isReady else { return }
        
        print("TTSManager: Critical instruction: \(text)")
        
        // Stop current speech
        if ttsState.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        performSpeak(text)
    }
    
    /// Speak emergency correction (bypasses ALL filtering)
    func speakEmergencyCorrection(_ text: String) {
        guard ttsState.isReady else { return }
        
        let textLower = text.lowercased()
        let emergencyKeywords = ["wrong direction", "backtrack"]
        
        guard emergencyKeywords.contains(where: { textLower.contains($0) }) else {
            speakCritical(text)
            return
        }
        
        print("TTSManager: Emergency correction: \(text)")
        
        // Stop any current speech immediately
        if ttsState.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        performSpeak(text)
    }
    
    /// Stop current speech
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        ttsState.isSpeaking = false
        print("TTSManager: Stopped")
    }
    
    /// Repeat the last spoken instruction
    func repeatLastInstruction() {
        if !ttsState.lastSpokenText.isEmpty {
            speak(ttsState.lastSpokenText, force: true)
        } else {
            speak("No previous instruction to repeat", force: true)
        }
    }
    
    /// Reset instruction message
    func resetInstruction() {
        speak("System reset.", force: true)
    }
    
    /// Enable or disable TTS
    func setEnabled(_ enabled: Bool) {
        ttsState.isEnabled = enabled
        
        if !enabled {
            stop()
        } else {
            speak("Voice guidance enabled", force: true)
        }
        
        print("TTSManager: \(enabled ? "Enabled" : "Disabled")")
    }
    
    /// Reset one-time instruction tracking
    func resetOneTimeInstructions() {
        spokenOneTimeInstructions.removeAll()
        lastNormalizedInstruction = ""
        lastTimedNeverMissInstructionTimes.removeAll()
        print("TTSManager: One-time instructions reset")
    }
    
    /// Check if a one-time instruction has been spoken
    func hasSpokenOneTimeInstruction(_ text: String) -> Bool {
        let normalized = normalizeOneTimeInstruction(text)
        return spokenOneTimeInstructions.contains(normalized)
    }
    
    /// Get TTS status information
    func getStatus() -> [String: Any] {
        return [
            "isReady": ttsState.isReady,
            "isEnabled": ttsState.isEnabled,
            "isSpeaking": ttsState.isSpeaking,
            "lastInstruction": String(ttsState.lastSpokenText.prefix(50)),
            "lastNormalizedInstruction": lastNormalizedInstruction,
            "timeSinceLastSpeech": ttsState.lastSpeechTime.map {
                "\(Int(Date().timeIntervalSince($0)))s"
            } ?? "Never"
        ]
    }
    
    /// Check if instruction is an emergency correction
    func isEmergencyCorrection(_ text: String) -> Bool {
        let textLower = text.lowercased()
        let emergencyKeywords = [
            "wrong direction", "backtrack", "danger", "stop immediately",
            "emergency", "overshoot", "reversed", "error recovery"
        ]
        return emergencyKeywords.contains { textLower.contains($0) }
    }
    
    /// Cleanup resources
    func cleanup() {
        stop()
        lastNormalizedInstruction = ""
        lastTimedNeverMissInstructionTimes.removeAll()
        spokenOneTimeInstructions.removeAll()
        ttsState = TTSState()
        print("TTSManager: Cleaned up")
    }
    
    // MARK: - Private Methods
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenContent, options: [.duckOthers, .mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            print("TTSManager: Failed to setup audio session: \(error)")
        }
    }
    
    private func performSpeak(_ text: String) {
        // Get appropriate voice based on language
        let voice: AVSpeechSynthesisVoice?
        if let languageManager = languageManager {
            let locale = languageManager.getCurrentLocale()
            voice = AVSpeechSynthesisVoice(language: locale.identifier)
        } else {
            voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = speechRate
        utterance.pitchMultiplier = speechPitch
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0.1
        
        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        synthesizer.speak(utterance)
        
        ttsState.lastSpokenText = text
        ttsState.lastSpeechTime = Date()
        
        // Track one-time instructions
        if isOneTimeInstruction(text) {
            let normalized = normalizeOneTimeInstruction(text)
            spokenOneTimeInstructions.insert(normalized)
        }
        
        print("TTSManager: Speaking: \(text)")
    }
    
    private func shouldSpeakWithPriority(_ text: String, currentTime: Date) -> Bool {
        // Always speak if nothing has been spoken
        guard let lastSpeechTime = ttsState.lastSpeechTime else {
            lastNormalizedInstruction = normalizeInstruction(text)
            if isNeverMissTimedInstruction(text) {
                lastTimedNeverMissInstructionTimes[lastNormalizedInstruction] = currentTime
            }
            return true
        }
        
        let timeSinceLastSpeech = currentTime.timeIntervalSince(lastSpeechTime)
        let normalizedText = normalizeInstruction(text)
        
        // One-time instructions
        if isOneTimeInstruction(text) {
            let normalizedOneTime = normalizeOneTimeInstruction(text)
            if spokenOneTimeInstructions.contains(normalizedOneTime) {
                return false
            }
            return true
        }
        
        // Never-miss no-consecutive
        if isNeverMissNoConsecutiveInstruction(text) {
            if normalizedText == lastNormalizedInstruction {
                return false
            }
            lastNormalizedInstruction = normalizedText
            return true
        }
        
        // Never-miss timed
        if isNeverMissTimedInstruction(text) {
            if let lastTime = lastTimedNeverMissInstructionTimes[normalizedText] {
                let timeSince = currentTime.timeIntervalSince(lastTime)
                if timeSince < minTimeBetweenNeverMissInstructions {
                    return false
                }
            }
            lastTimedNeverMissInstructionTimes[normalizedText] = currentTime
            lastNormalizedInstruction = normalizedText
            return true
        }
        
        // Critical instructions
        if isCriticalInstruction(text) {
            if timeSinceLastSpeech >= minTimeBetweenCriticalInstructions {
                lastNormalizedInstruction = normalizedText
                return true
            }
            return false
        }
        
        // Priority instructions
        if isPriorityInstruction(text) {
            if timeSinceLastSpeech >= minTimeBetweenPriorityInstructions {
                lastNormalizedInstruction = normalizedText
                return true
            }
            return false
        }
        
        // Regular instructions
        if timeSinceLastSpeech >= minTimeBetweenRegularInstructions {
            if normalizedText != lastNormalizedInstruction {
                lastNormalizedInstruction = normalizedText
                return true
            }
        }
        
        return false
    }
    
    private func normalizeInstruction(_ text: String) -> String {
        let normalized = text.lowercased()
        
        switch true {
        case normalized.contains("turn left"): return "turn_left"
        case normalized.contains("turn right"): return "turn_right"
        case normalized.contains("turn"): return "turn"
        case normalized.contains("your left") || normalized.contains("on your left"): return "location_left"
        case normalized.contains("your right") || normalized.contains("on your right"): return "location_right"
        case normalized.contains("prepare"): return "prepare"
        case normalized.contains("stop"): return "stop"
        case normalized.contains("danger"): return "danger"
        case normalized.contains("error"): return "error"
        case normalized.contains("keep moving"): return "keep_moving"
        case normalized.contains("wrong direction"): return "wrong_direction"
        case normalized.contains("make"): return "make"
        case normalized.contains("go straight") || normalized.contains("continue straight"): return "go_straight"
        case normalized.contains("u-turn"): return "u_turn"
        default: return normalized
        }
    }
    
    private func normalizeOneTimeInstruction(_ text: String) -> String {
        let normalized = text.lowercased()
        
        // Extract destination/location name if present
        let patterns = [
            "reached (.+)",
            "arrived at (.+)",
            "approaching (.+)",
            "destination (.+)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: normalized, options: [], range: NSRange(normalized.startIndex..., in: normalized)),
               let range = Range(match.range(at: 1), in: normalized) {
                return "reached_\(normalized[range])"
            }
        }
        
        return normalized
    }
    
    private func isOneTimeInstruction(_ text: String) -> Bool {
        let textLower = text.lowercased()
        return oneTimeKeywords.contains { textLower.contains($0) }
    }
    
    private func isNeverMissNoConsecutiveInstruction(_ text: String) -> Bool {
        let textLower = text.lowercased()
        return neverMissNoConsecutiveKeywords.contains { textLower.contains($0) }
    }
    
    private func isNeverMissTimedInstruction(_ text: String) -> Bool {
        let textLower = text.lowercased()
        return neverMissTimedKeywords.contains { keyword in
            switch keyword {
            case "turn left":
                return textLower.range(of: "\\bturn\\s+left\\b", options: .regularExpression) != nil
            case "turn right":
                return textLower.range(of: "\\bturn\\s+right\\b", options: .regularExpression) != nil
            default:
                return textLower.contains(keyword)
            }
        }
    }
    
    private func isNeverMissInstruction(_ text: String) -> Bool {
        return isNeverMissNoConsecutiveInstruction(text) || isNeverMissTimedInstruction(text)
    }
    
    private func isPriorityInstruction(_ text: String) -> Bool {
        let textLower = text.lowercased()
        return priorityKeywords.contains { textLower.contains($0) }
    }
    
    private func isCriticalInstruction(_ text: String) -> Bool {
        let textLower = text.lowercased()
        return criticalKeywords.contains { textLower.contains($0) }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSManager: AVSpeechSynthesizerDelegate {
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.ttsState.isSpeaking = true
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.ttsState.isSpeaking = false
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.ttsState.isSpeaking = false
        }
    }
}
