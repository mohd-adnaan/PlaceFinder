//
//  LanguageManager.swift
//  IndoorNavigationTACME
//
//  Manages bilingual support (English/French)
//

import Foundation
import Combine

/// Manages bilingual support for the navigation system
class LanguageManager: ObservableObject {
    
    // MARK: - Types
    
    enum Language: String, CaseIterable {
        case english = "en"
        case french = "fr"
        
        var displayName: String {
            switch self {
            case .english: return "English"
            case .french: return "Français"
            }
        }
        
        var locale: Locale {
            switch self {
            case .english: return Locale(identifier: "en-US")
            case .french: return Locale(identifier: "fr-CA")
            }
        }
    }
    
    // MARK: - Published Properties
    
    @Published private(set) var currentLanguage: Language = .english
    
    // MARK: - Private Properties
    
    // Translation cache to reduce API calls
    private var translationCache: [String: String] = [:]
    
    // Critical phrases for instant offline fallback
    private let criticalPhrases: [String: String] = [
        // Navigation - Core
        "turn left": "tournez à gauche",
        "turn right": "tournez à droite",
        "go straight": "allez tout droit",
        "continue straight": "continuez tout droit",
        
        // Navigation - Actions
        "arrived": "arrivé",
        "destination": "destination",
        "wrong direction": "mauvaise direction",
        "backtrack": "revenez en arrière",
        "keep moving": "continuez à avancer",
        "prepare to turn": "préparez-vous à tourner",
        "make a turn": "tournez",
        
        // System - Status
        "navigation started": "navigation démarrée",
        "navigation stopped": "navigation arrêtée",
        "listening": "en écoute",
        "processing": "traitement en cours",
        "error": "erreur",
        "ready to navigate": "prêt à naviguer",
        
        // Directions
        "north": "nord",
        "south": "sud",
        "east": "est",
        "west": "ouest",
        "ahead": "devant",
        "behind": "derrière",
        "left": "gauche",
        "right": "droite",
        
        // Numbers for clock directions
        "12 o'clock": "12 heures",
        "3 o'clock": "3 heures",
        "6 o'clock": "6 heures",
        "9 o'clock": "9 heures",
        
        // UI strings
        "Navigation Setup": "Configuration de navigation",
        "Source Location": "Lieu de départ",
        "Destination Location": "Lieu de destination",
        "Clock Directions": "Directions horaires",
        "Use Landmarks": "Utiliser repères",
        "Voice Guidance": "Guidage vocal",
        "Start Navigation": "Démarrer navigation",
        "Stop Navigation": "Arrêter navigation",
        "Current Instruction": "Instruction actuelle",
        "Ready to navigate": "Prêt à naviguer",
        "Initialize Server": "Initialiser serveur",
        "Server connected! Ready to start navigation.": "Serveur connecté! Prêt à démarrer.",
        "Interface reset successfully": "Interface réinitialisée avec succès",
        "Navigation system ready": "Système de navigation prêt"
    ]
    
    // Localized UI strings (for instant access)
    private let localizedStrings: [String: [Language: String]] = [
        "Navigation Setup": [.english: "Navigation Setup", .french: "Configuration de navigation"],
        "Source Location": [.english: "Source Location", .french: "Lieu de départ"],
        "Destination Location": [.english: "Destination Location", .french: "Lieu de destination"],
        "Clock Directions": [.english: "Clock Directions", .french: "Directions horaires"],
        "Use Landmarks": [.english: "Use Landmarks", .french: "Utiliser repères"],
        "Voice Guidance": [.english: "Voice Guidance", .french: "Guidage vocal"],
        "Start Navigation": [.english: "Start Navigation", .french: "Démarrer navigation"],
        "Stop Navigation": [.english: "Stop Navigation", .french: "Arrêter navigation"],
        "Initialize Server": [.english: "Initialize Server", .french: "Initialiser serveur"],
        "Ready to navigate": [.english: "Ready to navigate", .french: "Prêt à naviguer"]
    ]
    
    // MARK: - Public Methods
    
    /// Set the current language
    func setLanguage(_ language: Language) {
        currentLanguage = language
        print("LanguageManager: Language changed to \(language.displayName)")
    }
    
    /// Check if current language is French
    func isFrench() -> Bool {
        return currentLanguage == .french
    }
    
    /// Get current locale
    func getCurrentLocale() -> Locale {
        return currentLanguage.locale
    }
    
    /// Get localized UI string (instant, no API call)
    func getString(_ key: String) -> String {
        if let localizedDict = localizedStrings[key], let localized = localizedDict[currentLanguage] {
            return localized
        }
        
        // For French, try critical phrases
        if currentLanguage == .french {
            if let translation = criticalPhrases[key.lowercased()] {
                return translation
            }
        }
        
        return key
    }
    
    /// Translate text from English to French (async)
    func translateFromEnglish(_ text: String) async -> String {
        guard currentLanguage == .french else { return text }
        
        // Check cache first
        if let cached = translationCache[text] {
            return cached
        }
        
        // Check critical phrases
        if let critical = criticalPhrases[text.lowercased()] {
            translationCache[text] = critical
            return critical
        }
        
        // Try Gemini translation
        do {
            let translation = try await translateWithGemini(text: text, to: "French")
            translationCache[text] = translation
            return translation
        } catch {
            print("LanguageManager: Translation failed: \(error)")
            return text
        }
    }
    
    /// Translate text to English (async)
    func translateToEnglish(_ text: String) async -> String {
        guard currentLanguage == .french else { return text }
        
        do {
            return try await translateWithGemini(text: text, to: "English")
        } catch {
            print("LanguageManager: Translation failed: \(error)")
            return text
        }
    }
    
    /// Translate location name for backend (preserves format)
    func translateLocationName(_ location: String) async -> String {
        // Normalize the location
        let normalized = location.replacingOccurrences(of: " ", with: "").lowercased()
        
        // If it's already in English format (e.g., "room435"), return as-is
        let englishPattern = try? NSRegularExpression(pattern: "^[a-z]+\\d+$", options: [])
        if let matches = englishPattern?.matches(in: normalized, options: [], range: NSRange(normalized.startIndex..., in: normalized)),
           !matches.isEmpty {
            return normalized
        }
        
        // Translate and normalize
        let translated = await translateToEnglish(location)
        return translated.replacingOccurrences(of: " ", with: "").lowercased()
    }
    
    /// Preload common phrases for translation cache
    func preloadCommonPhrases() async {
        // Pre-populate cache with critical phrases
        for (english, french) in criticalPhrases {
            translationCache[english] = french
        }
        print("LanguageManager: Preloaded \(criticalPhrases.count) common phrases")
    }
    
    /// Toggle language between English and French
    func toggleLanguage() {
        switch currentLanguage {
        case .english:
            setLanguage(.french)
        case .french:
            setLanguage(.english)
        }
    }
    
    // MARK: - Private Methods
    
    private func translateWithGemini(text: String, to targetLanguage: String) async throws -> String {
        let systemPrompt = """
        You are a translation assistant. Translate the following text to \(targetLanguage).
        Return ONLY the translated text, no explanations or quotes.
        Keep technical terms and proper nouns as-is.
        """
        
        return try await GeminiService.shared.sendPrompt(text, systemPrompt: systemPrompt)
    }
}
