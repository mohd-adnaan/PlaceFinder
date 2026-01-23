//
//  StepCalibrationCard.swift
//  IndoorNavigationTACME
//
//  Step length calibration UI component (20m walk calibration)
//

import SwiftUI

struct StepCalibrationCard: View {
    let imuState: IMUState
    let onStartCalibration: () -> Void
    let onCompleteCalibration: () -> Void
    let onStopCalibration: () -> Void
    
    @State private var isExpanded = false
    
    private var calibrationProgress: Double {
        guard imuState.isCalibrating else { return 0 }
        // Assuming 20m calibration distance and ~0.75m average step
        let expectedSteps = 20.0 / 0.75 // ~27 steps
        return min(Double(imuState.calibrationStepCount) / expectedSteps, 1.0)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "figure.walk")
                        .font(.title2)
                        .foregroundColor(.blue)
                    
                    Text("Step Calibration")
                        .font(.headline)
                    
                    Spacer()
                    
                    // Status indicator
                    if imuState.isCalibrated {
                        Label("Calibrated", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else if imuState.isCalibrating {
                        Label("Calibrating...", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityHint("Tap to \(isExpanded ? "collapse" : "expand") step calibration options")
            
            // Expanded content
            if isExpanded {
                VStack(spacing: 16) {
                    Divider()
                    
                    // Current beta value
                    HStack {
                        Text("Current Beta Factor:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.3f", imuState.beta))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    
                    // Calibration progress (when calibrating)
                    if imuState.isCalibrating {
                        VStack(spacing: 8) {
                            ProgressView(value: calibrationProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                            
                            HStack {
                                Text("Steps: \(imuState.calibrationStepCount)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text("Walk 20 meters")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    // Calibration instructions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to calibrate:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            CalibrationStep(number: 1, text: "Tap 'Start Calibration'")
                            CalibrationStep(number: 2, text: "Walk exactly 20 meters")
                            CalibrationStep(number: 3, text: "Tap 'Complete' when done")
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // Calibration buttons
                    HStack(spacing: 12) {
                        if imuState.isCalibrating {
                            // Stop button
                            Button(action: onStopCalibration) {
                                Label("Cancel", systemImage: "xmark")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.red.opacity(0.1))
                                    .foregroundColor(.red)
                                    .cornerRadius(8)
                            }
                            
                            // Complete button
                            Button(action: onCompleteCalibration) {
                                Label("Complete", systemImage: "checkmark")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .disabled(imuState.calibrationStepCount < 5)
                        } else {
                            // Start button
                            Button(action: onStartCalibration) {
                                Label(imuState.isCalibrated ? "Recalibrate" : "Start Calibration",
                                      systemImage: "figure.walk")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
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

// MARK: - Calibration Step Component

private struct CalibrationStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Text("\(number).")
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 16)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

struct StepCalibrationCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Default state
            StepCalibrationCard(
                imuState: IMUState(
                    beta: 0.415,
                    isCalibrated: false,
                    isCalibrating: false,
                    calibrationStepCount: 0,
                    stepCount: 0,
                    position: Position(x: 0, y: 0),
                    bearing: 0
                ),
                onStartCalibration: {},
                onCompleteCalibration: {},
                onStopCalibration: {}
            )
            
            // Calibrating state
            StepCalibrationCard(
                imuState: IMUState(
                    beta: 0.415,
                    isCalibrated: false,
                    isCalibrating: true,
                    calibrationStepCount: 15,
                    stepCount: 15,
                    position: Position(x: 0, y: 0),
                    bearing: 0
                ),
                onStartCalibration: {},
                onCompleteCalibration: {},
                onStopCalibration: {}
            )
            
            // Calibrated state
            StepCalibrationCard(
                imuState: IMUState(
                    beta: 0.423,
                    isCalibrated: true,
                    isCalibrating: false,
                    calibrationStepCount: 0,
                    stepCount: 100,
                    position: Position(x: 5, y: 10),
                    bearing: 45
                ),
                onStartCalibration: {},
                onCompleteCalibration: {},
                onStopCalibration: {}
            )
        }
        .padding()
    }
}
