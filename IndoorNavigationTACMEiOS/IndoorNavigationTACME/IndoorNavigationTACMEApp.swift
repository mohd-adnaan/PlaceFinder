//
//  IndoorNavigationTACMEApp.swift
//  IndoorNavigationTACME
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
    
    init() {
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
                .onAppear {
                    setupManagers()
                }
        }
    }
    
    private func configureApp() {
        #if DEBUG
        print("")
        print("╔════════════════════════════════════════════════════════════╗")
        print("║       IndoorNavigationTACME - iOS Version                  ║")
        print("║       Server: Railway (indoornavigationtacme)              ║")
        print("╚════════════════════════════════════════════════════════════╝")
        print("")
        #endif
    }
    
    private func setupManagers() {
        print("🚀 === INITIALIZING PLACEFINDER iOS ===")
        print("")
        
        // === STEP 1: Load POI Names (CRITICAL) ===
        print("📍 STEP 1: Loading POI names from map_data.json...")
        let poiNames = loadPOINames()
        print("")
        
        // === STEP 2: Configure Managers ===
        print("🔧 STEP 2: Configuring managers...")
        
        calibrationManager.setSensorManager(sensorManager)
        print("   ✓ CalibrationManager")
        
        navigationManager.configure(
            calibrationManager: calibrationManager,
            sensorManager: sensorManager,
            ttsManager: ttsManager,
            qrDetector: qrDetector,
            languageManager: languageManager
        )
        print("   ✓ NavigationManager")
        
        conversationManager.configure(
            ttsManager: ttsManager,
            languageManager: languageManager
        )
        print("   ✓ ConversationManager")
        
        ttsManager.setLanguageManager(languageManager)
        print("   ✓ TTSManager")
        print("")
        
        // === STEP 3: Set POI Names ===
        print("📋 STEP 3: Setting POI names for navigation...")
        if let names = poiNames {
            navigationManager.setPOINames(names)
            print("   ✅ Loaded \(names.count) locations")
            print("   📍 Examples: \(names.prefix(3).joined(separator: ", "))...")
        } else {
            print("   ⚠️ NO POI NAMES LOADED - DROPDOWNS WILL BE EMPTY!")
            print("")
            print("   🔴 FIX REQUIRED:")
            print("      1. Add map_data.json to Xcode project")
            print("      2. Ensure 'Copy items if needed' is checked")
            print("      3. Ensure 'Add to targets' includes this app")
            print("      4. Check Build Phases → Copy Bundle Resources")
            navigationManager.setPOINames([])
        }
        print("")
        
        // === STEP 4: Preload Translations ===
        print("🌐 STEP 4: Preloading translations...")
        Task {
            await languageManager.preloadCommonPhrases()
            print("   ✓ Translations ready")
        }
        
        // === COMPLETE ===
        print("")
        print("═══════════════════════════════════════════════════════════════")
        if poiNames != nil {
            print("✅ IndoorNavigationTACME READY!")
            print("   → Select source and destination")
            print("   → Tap 'Initialize Server' to connect")
            print("   → Tap 'Start Navigation' to begin")
        } else {
            print("⚠️ IndoorNavigationTACME started with ERRORS")
            print("   Navigation will NOT work until map_data.json is added")
        }
        print("═══════════════════════════════════════════════════════════════")
        print("")
    }
    
    /// Load POI names with fallback options
    private func loadPOINames() -> [String]? {
        // Try primary file
        if let names = POIExtractor.extractPOINames(fileName: "map_data") {
            return names
        }
        
        // Try fallbacks
        let fallbacks = ["map_dataTr", "mapData", "MapData"]
        print("   ⚠️ Primary file not found, trying fallbacks...")
        
        for fallback in fallbacks {
            if let names = POIExtractor.extractPOINames(fileName: fallback) {
                print("   ✅ Found POIs in: \(fallback).json")
                return names
            }
        }
        
        return nil
    }
}
