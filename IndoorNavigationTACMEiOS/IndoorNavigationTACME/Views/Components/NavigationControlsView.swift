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
                    isLoading: initStep == .connecting || initStep == .serverResponse,
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
struct QRDetectionCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Scanning state
            QRDetectionCard(
                qrState: QRDetectionState(
                    isDetected: false,
                    lastDetectionTime: nil,
                    detectionCount: 0,
                    isScanning: true,
                    detectedContent: nil,
                    scanMode: .walking
                ),
                navigationState: NavigationState(
                    isNavigating: true,
                    initializationStep: .completed,
                    qrDetectionActive: true,
                    qrSyncMode: "SMART_SYNC"
                )
            )
            
            // Detected state
            QRDetectionCard(
                qrState: QRDetectionState(
                    isDetected: true,
                    lastDetectionTime: Date().addingTimeInterval(-15),
                    detectionCount: 5,
                    isScanning: true,
                    detectedContent: "QR_Id:https://qrco.de/bgErvr",
                    scanMode: .walking
                ),
                navigationState: NavigationState(
                    isNavigating: true,
                    initializationStep: .completed,
                    qrDetectionActive: true,
                    currentQRId: "bgErvr",
                    lastSentQRId: "bgErvr",
                    qrSyncMode: "SMART_SYNC"
                )
            )
        }
        .padding()
    }
}
