//
//  NavigationSettingsView.swift
//  IndoorNavigationTACME
//
//  Created by Mohammad Adnaan on 2026-03-09.
//
//  Settings page containing navigation setup, calibration, and preferences.
//  Previously displayed as the landing page — now accessed via gear icon.
//

import SwiftUI

struct NavigationSettingsView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var sensorManager: IMUSensorManager
    @EnvironmentObject var calibrationManager: IMUCalibrationManager
    @EnvironmentObject var ttsManager: TTSManager
    @EnvironmentObject var qrDetector: QRCodeDetector
    @EnvironmentObject var conversationManager: ConversationManager
    @EnvironmentObject var languageManager: LanguageManager

    @Environment(\.dismiss) var dismiss

    // Navigation input state
    @Binding var source: String
    @Binding var destination: String
    @Binding var useClockDirections: Bool
    @Binding var useLandmarks: Bool
    @Binding var voiceControlledMode: Bool
    @State private var didAutoSubmitCurrentCalibration: Bool = false

    private let autoCalibrationDistanceMeters: Double = 20.0

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Mode selection section
                    modeSection

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

                    // Step calibration
                    StepCalibrationCard(
                        imuState: sensorManager.imuState,
                        onStartCalibration: {
                            didAutoSubmitCurrentCalibration = false
                            sensorManager.startStepCalibration()
                            // Announce calibration start so the user knows to start walking
                            let msg = languageManager.currentLanguage == .french
                                ? "Calibration démarrée. Marchez 20 mètres."
                                : "Calibration started. Walk 20 meters."
                            ttsManager.speak(msg, force: true)
                        },
                        onCompleteCalibration: {
                            didAutoSubmitCurrentCalibration = false
                            sensorManager.completeStepCalibration()
                            // Announce result so visually impaired users get feedback
                            let beta = sensorManager.imuState.beta
                            let isValid = sensorManager.imuState.isStepCalibrationValid
                            let isFrench = languageManager.currentLanguage == .french
                            if isValid {
                                let msg = isFrench
                                    ? "Calibration terminée. Facteur bêta: \(String(format: "%.3f", beta))"
                                    : "Step calibration complete. Beta factor: \(String(format: "%.3f", beta))"
                                ttsManager.speakPriority(msg)
                            } else {
                                let msg = isFrench
                                    ? "Données insuffisantes. Réessayez."
                                    : "Not enough data collected. Please try again."
                                ttsManager.speakPriority(msg)
                            }
                        },
                        onStopCalibration: {
                            didAutoSubmitCurrentCalibration = false
                            sensorManager.stopStepCalibration()
                        }
                    )

                    // Status indicator
                    StatusIndicatorView(
                        isNavigating: navigationManager.navigationState.isNavigating,
                        isCalibrated: navigationManager.navigationState.isCalibrated,
                        ttsReady: ttsManager.ttsState.isReady,
                        qrDetectionActive: navigationManager.navigationState.qrDetectionActive,
                        qrDetected: qrDetector.detectionState.isDetected,
                        conversationActive: conversationManager.conversationState.isActive
                    )

                    // Current instruction display (with all 3 required params)
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

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle(languageManager.getString("Navigation Setup"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Close settings")
                }
            }
            .onChange(of: sensorManager.imuState.isCalibrating) { isCalibrating in
                if !isCalibrating {
                    didAutoSubmitCurrentCalibration = false
                }
            }
            .onChange(of: sensorManager.imuState.calibrationStepCount) { stepCount in
                guard sensorManager.imuState.isCalibrating else { return }
                guard !didAutoSubmitCurrentCalibration else { return }

                let estimatedDistance = Double(stepCount) * 0.65
                guard estimatedDistance >= autoCalibrationDistanceMeters else { return }

                didAutoSubmitCurrentCalibration = true
                sensorManager.completeStepCalibration()

                // ═══════════════════════════════════════════════════════════
                // ACCESSIBILITY FIX: Announce calibration completion via TTS.
                //
                // Root cause: Auto-calibration triggers silently. Sighted
                // users see the UI update; visually impaired users get zero
                // feedback. This spoken confirmation closes the gap.
                // ═══════════════════════════════════════════════════════════
                let beta = sensorManager.imuState.beta
                let isValid = sensorManager.imuState.isStepCalibrationValid
                let isFrench = languageManager.currentLanguage == .french

                if isValid {
                    let message = isFrench
                        ? "Calibration terminée. Facteur bêta: \(String(format: "%.3f", beta))"
                        : "Step calibration complete. Beta factor: \(String(format: "%.3f", beta))"
                    ttsManager.speakPriority(message)
                } else {
                    let message = isFrench
                        ? "Calibration terminée, mais les données sont insuffisantes."
                        : "Calibration finished, but not enough data was collected."
                    ttsManager.speakPriority(message)
                }
            }
        }
    }

    // MARK: - Mode Section

    private var modeSection: some View {
        VStack(spacing: 12) {
            // Voice Controlled Mode toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Voice Controlled Mode", systemImage: "mic.badge.plus")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.purple)

                    Text("Double-tap on home to set source & destination by voice")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: $voiceControlledMode)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                    .onChange(of: voiceControlledMode) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "voiceControlledMode")
                        let message = newValue
                            ? "Voice controlled mode enabled. Double-tap home screen to set route by voice."
                            : "Voice controlled mode disabled. Double-tap home screen for conversation."
                        ttsManager.speak(message, force: true)
                    }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Actions

    private func initializeNavigation() {
        // Persist selections
        UserDefaults.standard.set(useClockDirections, forKey: "useClockDirections")
        UserDefaults.standard.set(useLandmarks, forKey: "useLandmarks")

        Task {
            let result = await navigationManager.initializeWithServer(
                source: source,
                destination: destination,
                useClockDirections: useClockDirections,
                useLandmarks: useLandmarks,
                conversationMode: conversationManager.conversationState.isActive
            )

            if case .failure(let error) = result {
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

        ttsManager.speak(
            languageManager.getString("Interface reset successfully"),
            force: true
        )
    }
}
