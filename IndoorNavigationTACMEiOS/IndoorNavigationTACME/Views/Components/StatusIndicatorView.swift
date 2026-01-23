//
//  StatusIndicatorView.swift
//  IndoorNavigationTACME
//
//  Status indicators for navigation system state
//

import SwiftUI

struct StatusIndicatorView: View {
    let isNavigating: Bool
    let isCalibrated: Bool
    let ttsReady: Bool
    let qrDetectionActive: Bool
    let qrDetected: Bool
    let conversationActive: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Navigation status
            StatusBadge(
                icon: "location.fill",
                label: "Nav",
                isActive: isNavigating,
                activeColor: .green
            )
            
            // Calibration status
            StatusBadge(
                icon: "gyroscope",
                label: "Cal",
                isActive: isCalibrated,
                activeColor: .blue
            )
            
            // TTS status
            StatusBadge(
                icon: "speaker.wave.2.fill",
                label: "TTS",
                isActive: ttsReady,
                activeColor: .purple
            )
            
            // QR Detection status
            StatusBadge(
                icon: "qrcode.viewfinder",
                label: "QR",
                isActive: qrDetectionActive,
                activeColor: qrDetected ? .green : .orange
            )
            
            // Conversation status
            StatusBadge(
                icon: "mic.fill",
                label: "AI",
                isActive: conversationActive,
                activeColor: .blue
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Status Badge Component

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
                conversationActive: false
            )
            
            StatusIndicatorView(
                isNavigating: false,
                isCalibrated: false,
                ttsReady: true,
                qrDetectionActive: false,
                qrDetected: false,
                conversationActive: false
            )
        }
        .padding()
    }
}
