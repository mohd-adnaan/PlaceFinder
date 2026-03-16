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
            
            // Debug overlay — floating bug button + log panel
            DebugOverlayView()
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

                // Navigation controls row
                HStack(spacing: 16) {
                    // Stop button
                    Button(action: {
                        navigationManager.stopNavigation()
                        conversationManager.stopConversationMode()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .accessibilityLabel("Stop navigation")

                    // Repeat instruction button
                    Button(action: {
                        ttsManager.repeatLastInstruction()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Repeat")
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .cornerRadius(12)
                    }
                    .accessibilityLabel("Repeat last instruction")
                }

                // Segment / bearing info
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
