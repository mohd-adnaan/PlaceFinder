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
    @AppStorage("debugOverlayEnabled") private var debugOverlayEnabled: Bool = false
    // Set by the manual Complete/Cancel handlers, which speak their own
    // feedback; suppresses the auto-completion announcement in onChange.
    @State private var suppressCompletionAnnouncement: Bool = false
    @State private var showClearCalibrationConfirm: Bool = false

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
                            suppressCompletionAnnouncement = false
                            sensorManager.startStepCalibration()
                            // Announce calibration start so the user knows to start walking
                            let msg = languageManager.currentLanguage == .french
                                ? "Calibration démarrée. Marchez 20 mètres."
                                : "Calibration started. Walk 20 meters."
                            ttsManager.speak(msg, force: true)
                        },
                        onCompleteCalibration: {
                            suppressCompletionAnnouncement = true
                            sensorManager.completeStepCalibration()
                            announceCalibrationResult()
                        },
                        onStopCalibration: {
                            suppressCompletionAnnouncement = true
                            sensorManager.stopStepCalibration()
                            // Cancel discards the walk — say so, otherwise a blind
                            // user has no way to tell the tap registered.
                            let msg = languageManager.currentLanguage == .french
                                ? "Calibration annulée."
                                : "Calibration cancelled."
                            ttsManager.speakPriority(msg)
                        }
                    )

                    // Clear-calibration button (for handing the device to a new user).
                    // Disabled when no calibration is stored to prevent accidental taps,
                    // but always visible so visually impaired users can find it reliably.
                    clearCalibrationButton

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
                // The 20 m auto-complete now lives in IMUSensorManager (it keeps
                // working if this screen is dismissed mid-walk). When it fires,
                // isCalibrating flips false and we announce the result here.
                // Manual Complete/Cancel speak their own feedback and suppress this.
                if isCalibrating { return }
                if suppressCompletionAnnouncement {
                    suppressCompletionAnnouncement = false
                    return
                }
                announceCalibrationResult()
            }
            .alert(
                languageManager.currentLanguage == .french
                    ? "Effacer la calibration?"
                    : "Clear calibration?",
                isPresented: $showClearCalibrationConfirm
            ) {
                Button(
                    languageManager.currentLanguage == .french ? "Annuler" : "Cancel",
                    role: .cancel
                ) { }
                Button(
                    languageManager.currentLanguage == .french ? "Effacer" : "Clear",
                    role: .destructive,
                    action: performClearCalibration
                )
            } message: {
                Text(
                    languageManager.currentLanguage == .french
                        ? "La valeur de calibration enregistrée sera supprimée. Le prochain utilisateur devra recalibrer."
                        : "The stored calibration value will be removed. The next user will need to recalibrate."
                )
            }
        }
    }

    // MARK: - Clear Calibration Button

    /// Button shown beneath the StepCalibrationCard. Allows the device owner
    /// (e.g. researcher handing the phone to a new participant) to wipe the
    /// stored gait calibration so the next user can calibrate for themselves.
    /// Disabled-but-visible when no calibration is stored, so it remains
    /// findable by VoiceOver users without firing accidentally.
    private var clearCalibrationButton: some View {
        let isCalibrated = sensorManager.imuState.isStepCalibrationValid
        let isFrench = languageManager.currentLanguage == .french
        let title = isCalibrated
            ? (isFrench ? "Effacer la calibration enregistrée" : "Clear Saved Calibration")
            : (isFrench ? "Aucune calibration enregistrée" : "No Saved Calibration")
        let hint = isFrench
            ? "Supprime la valeur de calibration. À utiliser avant de remettre l'appareil à un nouvel utilisateur."
            : "Removes the stored calibration. Use before handing the device to a new user."

        return Button(action: { showClearCalibrationConfirm = true }) {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(isCalibrated ? 0.12 : 0.05))
            .foregroundColor(isCalibrated ? .red : .gray)
            .cornerRadius(10)
        }
        .disabled(!isCalibrated)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
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

            // Debug tools toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Debug Mode", systemImage: "terminal.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)

                    Text("Show a small logs button on the home screen")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: $debugOverlayEnabled)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .orange))
                    .onChange(of: debugOverlayEnabled) { newValue in
                        let message = newValue
                            ? "Debug mode enabled"
                            : "Debug mode disabled"
                        ttsManager.speak(message, force: true)
                    }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            // VoiceOver compatibility toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("VoiceOver Compatibility", systemImage: "accessibility")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.teal)

                    Text("Use VoiceOver announcements to avoid double speech")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { ttsManager.ttsState.voiceOverCompatibilityEnabled },
                    set: { newValue in
                        ttsManager.setVoiceOverCompatibilityEnabled(newValue)
                        let message = newValue
                            ? "VoiceOver compatibility enabled"
                            : "VoiceOver compatibility disabled"
                        ttsManager.speak(message, force: true)
                    }
                ))
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: .teal))
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            // AR Localization & Mapping Button
            NavigationLink(destination: ARMappingView(sourceSelection: $source)) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("AR Localization & Mapping", systemImage: "arkit")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)

                        Text("Scan the environment to build or load a localization map")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
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

    /// Wipe the persisted gait calibration and announce the result.
    /// Triggered from the destructive option in the clear-calibration alert.
    /// Speak the outcome of a finished calibration so visually impaired users
    /// get feedback whether it completed automatically or via the button.
    private func announceCalibrationResult() {
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
                ? "Données insuffisantes. Réessayez."
                : "Not enough data collected. Please try again."
            ttsManager.speakPriority(message)
        }
    }

    private func performClearCalibration() {
        // Clearing also aborts any in-progress walk; the "calibration cleared"
        // message below is the only announcement that should play.
        // (onStartCalibration resets this flag for the next walk.)
        suppressCompletionAnnouncement = true
        sensorManager.clearStepCalibration()

        let isFrench = languageManager.currentLanguage == .french
        let message = isFrench
            ? "Calibration effacée. Le prochain utilisateur devra calibrer en marchant 20 mètres."
            : "Calibration cleared. The next user will need to calibrate by walking 20 meters."
        ttsManager.speakPriority(message)
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
