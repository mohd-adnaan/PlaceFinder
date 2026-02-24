//
//  NavigationScreen.swift
//  IndoorNavigationTACME
//
//  Main navigation screen UI.
//  Double-tap anywhere → activates AI conversation orb (full-screen).
//  Double-tap again or press X → deactivates.
//  ConversationSection text-input box removed; voice-only via orb.
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

    // Orb overlay flag
    @State private var showConversationOrb: Bool = false

    var body: some View {
        ZStack {
            // ── Main navigation UI ─────────────────────────────────────
            DoubleTapContainer(onDoubleTap: toggleConversationMode) {
                ScrollView {
                    VStack(spacing: 16) {

                        headerView

                        // Double-tap hint — updates dynamically based on conversation state
                        doubleTapHintView

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

                        // QR detection status (when active or scanning)
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

            // ── Full-screen Conversation Orb overlay ───────────────────
            if showConversationOrb {
                ConversationOrbView(
                    conversationManager: conversationManager,
                    onDismiss: deactivateConversationMode
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showConversationOrb)
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

            // Language toggle
            Button(action: {
                languageManager.toggleLanguage()
                ttsManager.speak(
                    languageManager.currentLanguage == .french
                        ? "Langue changée en français"
                        : "Language changed to English",
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
        HStack {
            Image(systemName: conversationManager.conversationState.isActive
                  ? "waveform.circle.fill"
                  : "waveform.circle")
                .foregroundColor(
                    conversationManager.conversationState.isActive ? .green : .blue.opacity(0.7)
                )
            Text(
                conversationManager.conversationState.isActive
                    ? (languageManager.currentLanguage == .french
                       ? "Conversation active — double-cliquez pour quitter"
                       : "Conversation active — double-tap to exit")
                    : (languageManager.currentLanguage == .french
                       ? "Double-cliquez pour ouvrir l'assistant vocal"
                       : "Double-tap anywhere to open AI voice assistant")
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            conversationManager.conversationState.isActive
                ? Color.green.opacity(0.08)
                : Color.blue.opacity(0.06)
        )
        .cornerRadius(8)
        .animation(.easeInOut(duration: 0.2), value: conversationManager.conversationState.isActive)
    }

    // MARK: - Actions

    private func toggleConversationMode() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        if conversationManager.conversationState.isActive {
            deactivateConversationMode()
        } else {
            activateConversationMode()
        }
    }

    private func activateConversationMode() {
        showConversationOrb = true
        conversationManager.startConversationMode()
    }

    private func deactivateConversationMode() {
        conversationManager.stopConversationMode()
        showConversationOrb = false
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

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
            if case .failure(let error) = result {
                print("NavigationScreen: Init failed: \(error)")
            }
        }
    }

    private func startNavigation() {
        Task {
            let result = await navigationManager.startNavigationWithCalibration()
            if case .success = result {
                qrDetector.startScanning()
            } else if case .failure(let error) = result {
                print("NavigationScreen: Start failed: \(error)")
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
        deactivateConversationMode()
        qrDetector.stopScanning()
        sensorManager.resetPosition()
        calibrationManager.resetCalibration()
        source = ""
        destination = ""
        useClockDirections = false
        useLandmarks = false
        showAdvancedInfo = false
        ttsManager.speak("All settings reset")
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
