//
//  NavigationControlsView.swift
//  IndoorNavigationTACME
//
//  Navigation control buttons (initialize, start, stop, reset, repeat)
//

import SwiftUI

struct NavigationControlsView: View {
    let navigationState: NavigationState
    let conversationActive: Bool
    let canStart: Bool
    let onInitialize: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onReset: () -> Void
    let onRepeat: () -> Void
    
    private var initStep: InitStep {
        navigationState.initializationStep
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Primary action buttons
            primaryButtons
            
            // Secondary action buttons
            secondaryButtons
            
            // Status info
            if navigationState.isNavigating {
                statusInfo
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Primary Buttons
    
    private var primaryButtons: some View {
        HStack(spacing: 12) {
            // Initialize button
            if !navigationState.isInitialized {
                ActionButton(
                    title: "Initialize",
                    icon: "link",
                    color: .blue,
                    isEnabled: canStart,
                    isLoading: initStep == .connecting || initStep == .server_response,
                    action: onInitialize
                )
            }
            
            // Start Navigation button
            if navigationState.isInitialized && !navigationState.isNavigating {
                ActionButton(
                    title: "Start Navigation",
                    icon: "play.fill",
                    color: .green,
                    isEnabled: true,
                    isLoading: initStep == .calibrating,
                    action: onStart
                )
            }
            
            // Stop button (when navigating)
            if navigationState.isNavigating {
                ActionButton(
                    title: "Stop",
                    icon: "stop.fill",
                    color: .red,
                    isEnabled: true,
                    isLoading: false,
                    action: onStop
                )
            }
        }
    }
    
    // MARK: - Secondary Buttons
    
    private var secondaryButtons: some View {
        HStack(spacing: 12) {
            // Reset button
            SecondaryButton(
                title: "Reset",
                icon: "arrow.counterclockwise",
                color: .orange,
                isEnabled: true,
                action: onReset
            )
            
            // Repeat instruction button
            SecondaryButton(
                title: "Repeat",
                icon: "arrow.clockwise",
                color: .purple,
                isEnabled: navigationState.isNavigating,
                action: onRepeat
            )
        }
    }
    
    // MARK: - Status Info
    
    private var statusInfo: some View {
        VStack(spacing: 8) {
            Divider()
            
            HStack {
                // Session info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(navigationState.source.isEmpty ? "-" : 
                         "\(navigationState.source) → \(navigationState.destination)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // QR sync status
                if navigationState.qrDetectionActive {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("QR Sync")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(navigationState.currentQRId != nil ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            
                            Text(navigationState.qrSyncMode)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Current segment info
            if navigationState.currentSegmentId >= 0 {
                HStack {
                    Text("Segment: \(navigationState.currentSegmentId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if let bearing = navigationState.trueBearing {
                        Text("Bearing: \(Int(bearing))°")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Action Button Component

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let isEnabled: Bool
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                }
                
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isEnabled ? color : color.opacity(0.5))
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(title)
        .accessibilityHint(isLoading ? "Loading" : (isEnabled ? "Tap to \(title.lowercased())" : "Currently unavailable"))
    }
}

// MARK: - Secondary Button Component

struct SecondaryButton: View {
    let title: String
    let icon: String
    let color: Color
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isEnabled ? color.opacity(0.15) : Color.gray.opacity(0.1))
            .foregroundColor(isEnabled ? color : .gray)
            .cornerRadius(8)
        }
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityHint(isEnabled ? "Tap to \(title.lowercased())" : "Currently unavailable")
    }
}

// MARK: - Preview

struct NavigationControlsView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Initial state
            NavigationControlsView(
                navigationState: NavigationState(
                    isNavigating: false,
                    isInitialized: false,
                    isCalibrated: false,
                    currentInstruction: "Ready",
                    initializationStep: .notStarted
                ),
                conversationActive: false,
                canStart: true,
                onInitialize: {},
                onStart: {},
                onStop: {},
                onReset: {},
                onRepeat: {}
            )
            
            // Initialized, ready to start
            NavigationControlsView(
                navigationState: NavigationState(
                    isNavigating: false,
                    isInitialized: true,
                    isCalibrated: false,
                    currentInstruction: "Ready",
                    initializationStep: .completed
                ),
                conversationActive: false,
                canStart: true,
                onInitialize: {},
                onStart: {},
                onStop: {},
                onReset: {},
                onRepeat: {}
            )
            
            // Navigating
            NavigationControlsView(
                navigationState: NavigationState(
                    isNavigating: true,
                    isInitialized: true,
                    isCalibrated: true,
                    currentInstruction: "Continue straight",
                    source: "Room 101",
                    destination: "Elevator",
                    qrDetectionActive: true,
                    currentQRId: "QR_5",
                    qrSyncMode: "SMART_SYNC",
                    currentSegmentId: 2,
                    trueBearing: 45.5,
                    initializationStep: .completed
                ),
                conversationActive: false,
                canStart: true,
                onInitialize: {},
                onStart: {},
                onStop: {},
                onReset: {},
                onRepeat: {}
            )
        }
        .padding()
    }
}
