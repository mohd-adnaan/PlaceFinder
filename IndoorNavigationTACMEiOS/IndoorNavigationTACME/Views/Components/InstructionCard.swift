//
//  InstructionCard.swift
//  IndoorNavigationTACME
//
//  Displays current navigation instruction with visual feedback
//

import SwiftUI

struct InstructionCard: View {
    let instruction: String
    let isNavigating: Bool
    let errorMessage: String?
    
    @State private var isAnimating = false
    
    private var instructionType: InstructionType {
        let lowercased = instruction.lowercased()
        
        if lowercased.contains("arrived") || lowercased.contains("reached") ||
           lowercased.contains("arrivé") {
            return .arrived
        } else if lowercased.contains("turn") || lowercased.contains("tourner") {
            return .turn
        } else if lowercased.contains("continue") || lowercased.contains("straight") ||
                  lowercased.contains("continuer") {
            return .straight
        } else if lowercased.contains("warning") || lowercased.contains("attention") ||
                  lowercased.contains("careful") {
            return .warning
        } else if lowercased.contains("error") || errorMessage != nil {
            return .error
        } else {
            return .info
        }
    }
    
    private var iconName: String {
        switch instructionType {
        case .arrived: return "flag.checkered"
        case .turn: return "arrow.turn.up.right"
        case .straight: return "arrow.up"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }
    
    private var iconColor: Color {
        switch instructionType {
        case .arrived: return .green
        case .turn: return .orange
        case .straight: return .blue
        case .warning: return .yellow
        case .error: return .red
        case .info: return .gray
        }
    }
    
    private var backgroundColor: Color {
        switch instructionType {
        case .arrived: return .green.opacity(0.1)
        case .turn: return .orange.opacity(0.1)
        case .straight: return .blue.opacity(0.1)
        case .warning: return .yellow.opacity(0.1)
        case .error: return .red.opacity(0.1)
        case .info: return Color(.secondarySystemBackground)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main instruction card
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(iconColor.opacity(0.2))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: iconName)
                            .font(.title2)
                            .foregroundColor(iconColor)
                            .scaleEffect(isAnimating && isNavigating ? 1.1 : 1.0)
                    }
                    
                    // Instruction text
                    VStack(alignment: .leading, spacing: 4) {
                        if isNavigating {
                            Text("Current Instruction")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(instruction)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                }
                
                // Navigation status indicator
                if isNavigating {
                    HStack {
                        // Animated dots indicator
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { index in
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 6, height: 6)
                                    .opacity(isAnimating ? (index == 0 ? 1.0 : 0.3) : 0.3)
                                    .animation(
                                        Animation.easeInOut(duration: 0.5)
                                            .repeatForever()
                                            .delay(Double(index) * 0.15),
                                        value: isAnimating
                                    )
                            }
                        }
                        
                        Text("Navigating...")
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        Spacer()
                    }
                }
            }
            .padding()
            .background(backgroundColor)
            .cornerRadius(12)
            
            // Error message (if present)
            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .padding(.top, 8)
            }
        }
        .onAppear {
            if isNavigating {
                isAnimating = true
            }
        }
        .onChange(of: isNavigating) { navigating in
            isAnimating = navigating
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Navigation instruction: \(instruction)")
        .accessibilityHint(errorMessage != nil ? "Error: \(errorMessage!)" : "")
    }
}

// MARK: - Instruction Type

private enum InstructionType {
    case arrived
    case turn
    case straight
    case warning
    case error
    case info
}

// MARK: - Preview

struct InstructionCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            InstructionCard(
                instruction: "Ready to navigate",
                isNavigating: false,
                errorMessage: nil
            )
            
            InstructionCard(
                instruction: "Continue straight for 15 meters",
                isNavigating: true,
                errorMessage: nil
            )
            
            InstructionCard(
                instruction: "Turn right in 5 meters",
                isNavigating: true,
                errorMessage: nil
            )
            
            InstructionCard(
                instruction: "You have arrived at your destination",
                isNavigating: false,
                errorMessage: nil
            )
            
            InstructionCard(
                instruction: "Navigation paused",
                isNavigating: false,
                errorMessage: "Connection lost. Retrying..."
            )
        }
        .padding()
    }
}
