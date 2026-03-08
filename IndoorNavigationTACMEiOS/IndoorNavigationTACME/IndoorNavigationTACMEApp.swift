//
//  IndoorNavigationTACMEApp.swift
//  IndoorNavigationTACME
//
//  iOS Implementation of Indoor Navigation System
//  Converted from Android Kotlin app
//
//  Updated: Added VoiceNavigationManager for voice-controlled mode
//

import SwiftUI

@main
struct IndoorNavigationTACMEApp: App {
    // State objects for dependency injection
    @StateObject private var navigationManager = NavigationManager()
    @StateObject private var sensorManager = IMUSensorManager()
    @StateObject private var calibrationManager = IMUCalibrationManager()
    @StateObject private var ttsManager = TTSManager()
    @StateObject private var qrDetector = QRCodeDetector()
    @StateObject private var conversationManager = ConversationManager()
    @StateObject private var languageManager = LanguageManager()
    @StateObject private var voiceNavManager = VoiceNavigationManager()

    init() {
        // Configure app-wide settings
        configureApp()
    }

    var body: some Scene {
        WindowGroup {
            NavigationScreen()
                .environmentObject(navigationManager)
                .environmentObject(sensorManager)
                .environmentObject(calibrationManager)
                .environmentObject(ttsManager)
                .environmentObject(qrDetector)
                .environmentObject(conversationManager)
                .environmentObject(languageManager)
                .environmentObject(voiceNavManager)
                .onAppear {
                    setupManagers()
                }
                .preferredColorScheme(.dark) // Force dark mode for the immersive landing page
        }
    }

    private func configureApp() {
        #if DEBUG
        print("IndoorNavigationTACME: Debug mode enabled")
        #endif
    }

    private func setupManagers() {
        // Wire up manager dependencies
        calibrationManager.setSensorManager(sensorManager)
        navigationManager.configure(
            calibrationManager: calibrationManager,
            sensorManager: sensorManager,
            ttsManager: ttsManager,
            qrDetector: qrDetector,
            languageManager: languageManager
        )
        conversationManager.configure(
            ttsManager: ttsManager,
            languageManager: languageManager
        )
        voiceNavManager.configure(
            ttsManager: ttsManager,
            languageManager: languageManager
        )
        ttsManager.setLanguageManager(languageManager)

        // Load POI names
        if let poiNames = POIExtractor.extractPOINames(fileName: "map_data") {
            navigationManager.setPOINames(poiNames)
        }

        // Preload common phrases for translation
        Task {
            await languageManager.preloadCommonPhrases()
        }

        print("IndoorNavigationTACME: All managers initialized successfully")
    }
}




