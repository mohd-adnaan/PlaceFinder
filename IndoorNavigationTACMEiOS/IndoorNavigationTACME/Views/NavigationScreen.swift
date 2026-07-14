//
//  NavigationScreen.swift
//  IndoorNavigationTACME
//
//  Created by Mohammad Adnaan on 2026-03-09.
//
//  Root container view.
//  Hosts the minimalist LandingPageView and presents SettingsView as a sheet.
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
    @EnvironmentObject var voiceNavManager: VoiceNavigationManager

    // Persistent UI state
    @State private var showSettings: Bool = false
    @State private var source: String = ""
    @State private var destination: String = ""
    @State private var useClockDirections: Bool = UserDefaults.standard.bool(forKey: "useClockDirections")
    @State private var useLandmarks: Bool = UserDefaults.standard.bool(forKey: "useLandmarks")
    @AppStorage("voiceControlledMode") private var voiceControlledMode: Bool = false
    @AppStorage("debugOverlayEnabled") private var debugOverlayEnabled: Bool = false

    var body: some View {
        ZStack {
            // Main landing page
            LandingPageView(
                showSettings: $showSettings,
                voiceControlledMode: $voiceControlledMode
            )

            // Navigation overlay when actively navigating
            if navigationManager.navigationState.isNavigating {
                navigationOverlay
            }
            
            if debugOverlayEnabled {
                DebugOverlayView()
            }
        }
        .sheet(isPresented: $showSettings) {
            // FIX: Use NavigationSettingsView (renamed to avoid conflict)
            NavigationSettingsView(
                source: $source,
                destination: $destination,
                useClockDirections: $useClockDirections,
                useLandmarks: $useLandmarks,
                voiceControlledMode: $voiceControlledMode
            )
        }
        .onAppear {
            sensorManager.startSensors()
        }
        .onDisappear {
            sensorManager.stopSensors()
        }
    }

    // MARK: - Navigation Overlay

    /// Floating overlay shown during active navigation on top of the landing page
    private var navigationOverlay: some View {
        VStack {
            Spacer()

            VStack(spacing: 12) {
                // FIX: currentInstruction is String (not Optional) — use isEmpty check
                let instruction = navigationManager.navigationState.currentInstruction
                if !instruction.isEmpty && instruction != "Ready to navigate" {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.title3)
                            .foregroundColor(.blue)

                        Text(instruction)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6).opacity(0.95))
                    .cornerRadius(16)
                }

                // Navigation controls — large stacked buttons sized for blind/low-vision
                // users to find by touch. Vertical layout gives each button the full
                // width of the screen rather than a quarter, and the 64pt minimum
                // height clears Apple's 44pt accessible-target guideline with margin.
                VStack(spacing: 12) {
                    // Stop button — destructive, top of stack so it's reachable
                    // with a single thumb sweep from the bottom of the device.
                    Button(action: {
                        navigationManager.stopNavigation()
                        conversationManager.stopConversationMode()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "stop.fill")
                                .font(.title2)
                            Text("Stop Navigation")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                    .accessibilityLabel("Stop navigation")
                    .accessibilityHint("Ends the current route and exits voice navigation.")

                    // Repeat instruction button — large secondary control.
                    Button(action: {
                        ttsManager.repeatLastInstruction()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.clockwise")
                                .font(.title2)
                            Text("Repeat Instruction")
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Color.purple.opacity(0.18))
                        .foregroundColor(.purple)
                        .cornerRadius(14)
                    }
                    .accessibilityLabel("Repeat last instruction")
                    .accessibilityHint("Speaks the most recent navigation instruction again.")
                }

                // Segment / bearing info — sighted-debug only; hidden from VoiceOver
                // so blind users don't have to scroll past it to reach controls.
                if navigationManager.navigationState.currentSegmentId >= 0 {
                    HStack {
                        Text("Segment: \(navigationManager.navigationState.currentSegmentId)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        if let bearing = navigationManager.navigationState.trueBearing {
                            Text("Bearing: \(Int(bearing))°")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if navigationManager.navigationState.qrDetectionActive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(navigationManager.navigationState.currentQRId != nil
                                          ? Color.green : Color.orange)
                                    .frame(width: 6, height: 6)
                                Text("QR")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
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
            .environmentObject(VoiceNavigationManager())
    }
}
