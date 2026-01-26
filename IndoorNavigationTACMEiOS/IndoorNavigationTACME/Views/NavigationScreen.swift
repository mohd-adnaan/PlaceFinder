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
                    
                    // Navigation input section
                    NavigationInputSection(
                        source: $source,
                        destination: $destination,
                        useClockDirections: $useClockDirections,
                        useLandmarks: $useLandmarks,
                        ttsEnabled: ttsManager.ttsState.isEnabled,
                        poiNames: navigationManager.poiNames,
                        onTtsEnabledChange: { ttsManager.setEnabled($0) }
                    )
                    
                    // Step calibration card
                    StepCalibrationCard(
                        imuState: sensorManager.imuState,
                        onStartCalibration: { sensorManager.startStepCalibration() },
                        onCompleteCalibration: { sensorManager.completeStepCalibration() },
                        onStopCalibration: { sensorManager.stopStepCalibration() }
                    )
                    
                    // Current instruction display
                    InstructionCard(
                        instruction: navigationManager.navigationState.currentInstruction,
                        isNavigating: navigationManager.navigationState.isNavigating,
                        errorMessage: navigationManager.navigationState.errorMessage
                    )
                    
                    // Navigation controls
                    NavigationControlsView(
                        navigationState: navigationManager.navigationState,
                        conversationActive: conversationManager.conversationState.isActive,
                        canStart: !source.isEmpty && !destination.isEmpty,
                        onInitialize: initializeNavigation,
                        onStart: startNavigation,
                        onStop: { navigationManager.stopNavigation() },
                        onReset: resetAll,
                        onRepeat: { ttsManager.repeatLastInstruction() }
                    )
                    
                    // QR Detection card (when active)
                    if navigationManager.navigationState.qrDetectionActive {
                        QRDetectionCard(
                            qrState: qrDetector.detectionState,
                            navigationState: navigationManager.navigationState
                        )
                    }
                    
                    // Conversation section (when active)
                    if conversationManager.conversationState.isActive {
                        ConversationSection(
                            conversationState: conversationManager.conversationState,
                            onSendMessage: { conversationManager.processTextInput($0) }
                        )
                    }
                    
                    Spacer(minLength: 50)
                }
                .padding()
            }
        }
        .onAppear {
            sensorManager.startSensors()
        }
        .onDisappear {
            sensorManager.stopSensors()
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            Text(languageManager.getString("Navigation Setup"))
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            // Language toggle button
            Button(action: {
                languageManager.toggleLanguage()
                ttsManager.speak(
                    languageManager.currentLanguage == .french ?
                        "Langue changée en français" : "Language changed to English",
                    force: true
                )
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                    Text(languageManager.currentLanguage == .english ? "EN" : "FR")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Reset button
            Button(action: resetAll) {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }
    
    private var doubleTapHintView: some View {
        Text(languageManager.currentLanguage == .french ?
             "Double-cliquez pour activer la saisie vocale" :
             "Double-tap anywhere to activate voice input")
            .font(.caption)
            .foregroundColor(.blue)
            .padding(.vertical, 4)
    }
    
    // MARK: - Actions
    
    private func activateVoiceInput() {
        if conversationManager.conversationState.isActive {
            if conversationManager.conversationState.isListening {
                conversationManager.stopListening()
            } else {
                conversationManager.startListening()
            }
            showDoubleTapFeedback = true
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showDoubleTapFeedback = false
            }
        }
    }
    
    private func initializeNavigation() {
        Task {
            let result = await navigationManager.initializeWithServer(
                source: source,
                destination: destination,
                useClockDirections: useClockDirections,
                useLandmarks: useLandmarks,
                conversationMode: conversationManager.conversationState.isActive
            )
            
            if case .failure(let error) = result {
                // Show error toast
                print("Navigation initialization failed: \(error)")
            }
        }
    }
    
    private func startNavigation() {
        Task {
            let result = await navigationManager.startNavigationWithCalibration()
            
            if case .failure(let error) = result {
                print("Navigation start failed: \(error)")
            }
        }
    }
    
    private func resetAll() {
        navigationManager.stopNavigation()
        conversationManager.stopConversationMode()
        sensorManager.resetPosition()
        calibrationManager.resetCalibration()
        qrDetector.resetDetection()
        
        source = ""
        destination = ""
        useClockDirections = false
        useLandmarks = false
        showAdvancedInfo = false
    }
}

// MARK: - Double Tap Container

struct DoubleTapContainer<Content: View>: View {
    let onDoubleTap: () -> Void
    let content: () -> Content
    
    @State private var tapCount = 0
    @State private var lastTapTime: Date?
    private let multiTapTimeout: TimeInterval = 0.5
    
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
