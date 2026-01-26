//
//  QRDetectionCard.swift
//  IndoorNavigationTACME
//
//  QR code detection status and details card
//

import SwiftUI

struct QRDetectionCard: View {
    let qrState: QRDetectionState
    let navigationState: NavigationState
    
    @State private var showDetails = false
    
    private var timeSinceDetection: String {
        guard qrState.isDetected,
              let lastTime = qrState.lastDetectionTime else {
            return "-"
        }
        
        let elapsed = Date().timeIntervalSince(lastTime)
        if elapsed < 60 {
            return "\(Int(elapsed))s ago"
        } else {
            return "\(Int(elapsed / 60))m ago"
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            Button(action: { withAnimation { showDetails.toggle() } }) {
                HStack {
                    // QR icon with status
                    ZStack {
                        Circle()
                            .fill(qrState.isDetected ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title2)
                            .foregroundColor(qrState.isDetected ? .green : .orange)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("QR Detection")
                            .font(.headline)
                        
                        Text(qrState.isDetected ? "Active - Last: \(timeSinceDetection)" : "Scanning...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Detection count badge
                    if qrState.detectionCount > 0 {
                        Text("\(qrState.detectionCount)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Details section
            if showDetails {
                VStack(spacing: 12) {
                    Divider()
                    
                    // Current QR ID
                    DetailRow(
                        label: "Current QR ID",
                        value: navigationState.currentQRId ?? "None",
                        icon: "qrcode",
                        valueColor: navigationState.currentQRId != nil ? .green : .secondary
                    )
                    
                    // Last sent QR ID
                    DetailRow(
                        label: "Last Sent to Server",
                        value: navigationState.lastSentQRId ?? "None",
                        icon: "arrow.up.circle",
                        valueColor: .blue
                    )
                    
                    // Sync mode
                    DetailRow(
                        label: "Sync Mode",
                        value: navigationState.qrSyncMode,
                        icon: "arrow.triangle.2.circlepath",
                        valueColor: .purple
                    )
                    
                    // Detected content
                    if let content = qrState.detectedContent, !content.isEmpty {
                        DetailRow(
                            label: "Raw Content",
                            value: content.count > 50 ? String(content.prefix(50)) + "..." : content,
                            icon: "text.alignleft",
                            valueColor: .secondary
                        )
                    }
                    
                    // Scan statistics
                    HStack(spacing: 20) {
                        StatBox(label: "Total Scans", value: "\(qrState.detectionCount)", color: .blue)
                        StatBox(label: "Frame Rate", value: qrState.isScanning ? "Active" : "Paused", color: .green)
                        StatBox(label: "Mode", value: qrState.scanMode == .walking ? "Walk" : "Full", color: .orange)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Detail Row Component

private struct DetailRow: View {
    let label: String
    let value: String
    let icon: String
    let valueColor: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(valueColor)
        }
    }
}

// MARK: - Stat Box Component

private struct StatBox: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}
