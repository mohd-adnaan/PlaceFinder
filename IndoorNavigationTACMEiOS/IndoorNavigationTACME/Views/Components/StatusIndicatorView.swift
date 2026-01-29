//
//  StatusIndicatorView.swift
//  IndoorNavigationTACME
//
//  Status indicators for navigation system state
//
//
//  StatusIndicatorView.swift
//  IndoorNavigationTACME
//
//  Status indicators for navigation system state - NOW INTERACTIVE
//

import SwiftUI

struct StatusIndicatorView: View {
    let isNavigating: Bool
    let isCalibrated: Bool
    let ttsReady: Bool
    let qrDetectionActive: Bool
    let qrDetected: Bool
    let conversationActive: Bool
    
    // Action callbacks for making buttons interactive
    var onNavTap: (() -> Void)?
    var onCalTap: (() -> Void)?
    var onTtsTap: (() -> Void)?
    var onQrTap: (() -> Void)?
    var onAiTap: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 12) {
            // Navigation status - tappable
            InteractiveStatusBadge(
                icon: "location.fill",
                label: "Nav",
                isActive: isNavigating,
                activeColor: .green,
                onTap: onNavTap
            )
            
            // Calibration status - tappable
            InteractiveStatusBadge(
                icon: "gyroscope",
                label: "Cal",
                isActive: isCalibrated,
                activeColor: .blue,
                onTap: onCalTap
            )
            
            // TTS status - tappable
            InteractiveStatusBadge(
                icon: "speaker.wave.2.fill",
                label: "TTS",
                isActive: ttsReady,
                activeColor: .purple,
                onTap: onTtsTap
            )
            
            // QR Detection status - tappable
            InteractiveStatusBadge(
                icon: "qrcode.viewfinder",
                label: "QR",
                isActive: qrDetectionActive,
                activeColor: qrDetected ? .green : .orange,
                onTap: onQrTap
            )
            
            // Conversation status - tappable
            InteractiveStatusBadge(
                icon: "mic.fill",
                label: "AI",
                isActive: conversationActive,
                activeColor: .blue,
                onTap: onAiTap
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Interactive Status Badge Component

struct InteractiveStatusBadge: View {
    let icon: String
    let label: String
    let isActive: Bool
    let activeColor: Color
    var onTap: (() -> Void)?
    
    var body: some View {
        Button(action: {
            onTap?()
        }) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(isActive ? activeColor.opacity(0.2) : Color.gray.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(isActive ? activeColor : .gray)
                }
                
                Text(label)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(isActive ? activeColor : .gray)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(isActive ? "active" : "inactive")")
        .accessibilityHint(onTap != nil ? "Double tap to toggle" : "")
    }
}

// MARK: - Legacy non-interactive badge for backward compatibility

struct StatusBadge: View {
    let icon: String
    let label: String
    let isActive: Bool
    let activeColor: Color
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isActive ? activeColor.opacity(0.2) : Color.gray.opacity(0.1))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(isActive ? activeColor : .gray)
            }
            
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(isActive ? activeColor : .gray)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(isActive ? "active" : "inactive")")
    }
}

// MARK: - Preview
struct StatusIndicatorView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            StatusIndicatorView(
                isNavigating: true,
                isCalibrated: true,
                ttsReady: true,
                qrDetectionActive: true,
                qrDetected: true,
                conversationActive: false,
                onNavTap: { print("Nav tapped") },
                onCalTap: { print("Cal tapped") },
                onTtsTap: { print("TTS tapped") },
                onQrTap: { print("QR tapped") },
                onAiTap: { print("AI tapped") }
            )
            
            StatusIndicatorView(
                isNavigating: false,
                isCalibrated: false,
                ttsReady: false,
                qrDetectionActive: false,
                qrDetected: false,
                conversationActive: true
            )
        }
        .padding()
    }
}
