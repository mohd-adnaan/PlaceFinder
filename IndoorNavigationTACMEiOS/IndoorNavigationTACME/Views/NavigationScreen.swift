//
//  NavigationScreen.swift
//  IndoorNavigationTACME
//
//  Main navigation screen UI
//

import SwiftUI
import UIKit

struct NavigationScreen: View {
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var sensorManager: IMUSensorManager
    @EnvironmentObject var calibrationManager: IMUCalibrationManager
    @EnvironmentObject var ttsManager: TTSManager
    @EnvironmentObject var qrDetector: QRCodeDetector
    @EnvironmentObject var conversationManager: ConversationManager
    @EnvironmentObject var languageManager: LanguageManager
    
    // Local UI state
    @State private var source: String = ""
    @State private var destination: String = ""
    @State private var useClockDirections: Bool = false
    @State private var useLandmarks: Bool = false
    @State private var showAdvancedInfo: Bool = false
    @State private var showDoubleTapFeedback: Bool = false
    @State private var showCalibrationSheet: Bool = false
    @State private var showQRScanner: Bool = false
    
    var body: some View {
        DoubleTapContainer(
            onDoubleTap: activateVoiceInput
        ) {
            ScrollView {
                VStack(spacing: 16) {
                    // Header with language toggle
                    headerView
                    
                    // Double-tap hint (when conversation active)
                    if conversationManager.conversationState.isActive {
                        doubleTapHintView
                    }
                    
                    // Status indicator
                    StatusIndicatorView(
                        isNavigating: navigationManager.navigationState.isNavigating,
                        isCalibrated: navigationManager.navigationState.isCalibrated,
                        ttsReady: ttsManager.ttsState.isReady,
                        qrDetectionActive: navigationManager.navigationState.qrDetectionActive,
                        qrDetected: qrDetector.detectionState.isDetected,
                        conversationActive: conversationManager.conversationState.isActive
                    )
                    
                    // Navigation input section with proper dropdowns
                    NavigationInputSection(
                        source: $source,
                        destination: $destination,
                        useClockDirections: $useClockDirections,
                        useLandmarks: $useLandmarks,
                        ttsEnabled: ttsManager.ttsState.isEnabled,
                        poiNames: navigationManager.poiNames,
                        onTtsEnabledChange: { ttsManager.setEnabled($0) }
                    )
                    
                    // Step calibration card - with real-time updates
                    StepCalibrationCard(
                        imuState: sensorManager.imuState,
                        onStartCalibration: { sensorManager.startStepCalibration() },
                        onCompleteCalibration: { sensorManager.completeStepCalibration() },
                        onStopCalibration: { sensorManager.stopStepCalibration() }
                    )
                    
                    // AI Conversation section
                    if conversationManager.conversationState.isActive {
                        ConversationSection(
                            conversationState: conversationManager.conversationState,
                            onSendMessage: { message in
                                conversationManager.processTextInput(message)
                            }
                        )
                    }
                    
                    // Current instruction display
                    InstructionCard(
                        instruction: navigationManager.navigationState.currentInstruction,
                        isNavigating: navigationManager.navigationState.isNavigating,
                        errorMessage: navigationManager.navigationState.errorMessage
                    )
                    
                    // QR detection status (when active)
                    if navigationManager.navigationState.qrDetectionActive || qrDetector.detectionState.isScanning {
                        QRDetectionCard(
                            qrState: qrDetector.detectionState,
                            navigationState: navigationManager.navigationState
                        )
                    }
                    
                    // Navigation controls
                    NavigationControlsView(
                        navigationState: navigationManager.navigationState,
                        conversationActive: conversationManager.conversationState.isActive,
                        canStart: !source.isEmpty && !destination.isEmpty,
                        onInitialize: initializeServer,
                        onStart: startNavigation,
                        onStop: stopNavigation,
                        onReset: resetAll,
                        onRepeat: { ttsManager.repeatLastInstruction() }
                    )
                    
                    Spacer(minLength: 50)
                }
                .padding()
            }
        }
        .onAppear {
            // Initialize sensors when view appears
            sensorManager.startSensors()
        }
        .onDisappear {
            // Stop sensors when view disappears
            sensorManager.stopSensors()
        }
        .overlay(doubleTapFeedbackOverlay)
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Text("Navigation Setup")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Spacer()
            
            // Language toggle button
            Button(action: toggleLanguage) {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                    Text(languageManager.currentLanguage == .english ? "EN" : "FR")
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Refresh button
            Button(action: refreshState) {
                Image(systemName: "arrow.clockwise")
                    .font(.title2)
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Double-tap hint view
    
    private var doubleTapHintView: some View {
        HStack {
            Image(systemName: "hand.tap.fill")
                .foregroundColor(.blue)
            Text(languageManager.currentLanguage == .french ?
                 "Double-tapez pour activer la saisie vocale" :
                 "Double-tap anywhere to activate voice input")
                .font(.caption)
                .foregroundColor(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Double-tap feedback overlay
    
    private var doubleTapFeedbackOverlay: some View {
        Group {
            if showDoubleTapFeedback {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "mic.fill")
                        Text("Voice input activated")
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                    Spacer()
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showDoubleTapFeedback)
    }
    
    // MARK: - Navigation Actions
    
    private func initializeServer() {
        guard !source.isEmpty && !destination.isEmpty else {
            ttsManager.speak("Please enter both source and destination")
            return
        }
        
        Task {
            let result = await navigationManager.initializeWithServer(
                source: source,
                destination: destination,
                useClockDirections: useClockDirections,
                useLandmarks: useLandmarks,
                conversationMode: conversationManager.conversationState.isActive
            )
            
            switch result {
            case .success:
                print("NavigationScreen: Server initialized successfully")
            case .failure(let error):
                print("NavigationScreen: Server initialization failed: \(error)")
                await MainActor.run {
                    ttsManager.speakCritical("Server connection failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func startNavigation() {
        Task {
            let result = await navigationManager.startNavigationWithCalibration()
            
            switch result {
            case .success:
                qrDetector.startScanning()
                print("NavigationScreen: Navigation started")
            case .failure(let error):
                print("NavigationScreen: Navigation start failed: \(error)")
                await MainActor.run {
                    ttsManager.speakCritical("Failed to start navigation: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func stopNavigation() {
        navigationManager.stopNavigation()
        qrDetector.stopScanning()
        ttsManager.speak("Navigation stopped")
    }
    
    private func resetAll() {
        navigationManager.stopNavigation()
        conversationManager.stopConversationMode()
        qrDetector.stopScanning()
        sensorManager.resetPosition()
        calibrationManager.resetCalibration()
        source = ""
        destination = ""
        useClockDirections = false
        useLandmarks = false
        ttsManager.speak("All settings reset")
    }
    
    private func toggleLanguage() {
        languageManager.toggleLanguage()
        let newLang = languageManager.currentLanguage == .english ? "English" : "Français"
        ttsManager.speak("Language changed to \(newLang)")
    }
    
    private func refreshState() {
        sensorManager.resetPosition()
        qrDetector.resetDetection()
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        ttsManager.speak("State refreshed")
    }
    
    private func activateVoiceInput() {
        guard conversationManager.conversationState.isActive else {
            conversationManager.startConversationMode()
            return
        }
        
        withAnimation {
            showDoubleTapFeedback = true
        }
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        conversationManager.startListening()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showDoubleTapFeedback = false
            }
        }
    }
}

// MARK: - Double Tap Container

struct DoubleTapContainer<Content: View>: View {
    let onDoubleTap: () -> Void
    let content: () -> Content
    
    var body: some View {
        content()
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                onDoubleTap()
            }
    }
}

// MARK: - Preview

struct NavigationScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationScreen()
            .environmentObject(NavigationManager())
            .environmentObject(IMUSensorManager())
            .environmentObject(IMUCalibrationManager())
            .environmentObject(TTSManager())
            .environmentObject(QRCodeDetector())
            .environmentObject(ConversationManager())
            .environmentObject(LanguageManager())
    }
}
