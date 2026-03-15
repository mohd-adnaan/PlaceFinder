//
//  StepCalibrationCard.swift
//  IndoorNavigationTACME
//
//  Step length calibration UI component (20m walk calibration)
//  FIXED: Now shows real-time step count and distance updates
//         Auto-completes when 20 meters is reached
//

import SwiftUI

struct StepCalibrationCard: View {
    let imuState: IMUState
    let onStartCalibration: () -> Void
    let onCompleteCalibration: () -> Void
    let onStopCalibration: () -> Void
    
    @State private var isExpanded = false
    
    // Calibration constants
    private let calibrationDistance: Double = 20.0 // meters
    private let averageStepLength: Double = 0.65 // meters (used for progress estimation)
    
    // Computed properties for progress tracking
    private var calibrationProgress: Double {
        guard imuState.isCalibrating else { return 0 }
        let estimatedDistance = Double(imuState.calibrationStepCount) * averageStepLength
        return min(estimatedDistance / calibrationDistance, 1.0)
    }
    
    private var estimatedDistanceCovered: Double {
        return Double(imuState.calibrationStepCount) * averageStepLength
    }
    
    private var remainingDistance: Double {
        return max(calibrationDistance - estimatedDistanceCovered, 0)
    }
    
    private var isCalibrationReady: Bool {
        return estimatedDistanceCovered >= calibrationDistance
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
                    if imuState.isStepCalibrationValid {
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
                    
                    // Real-time calibration progress (when calibrating)
                    if imuState.isCalibrating {
                        VStack(spacing: 12) {
                            // Progress bar
                            VStack(spacing: 4) {
                                ProgressView(value: calibrationProgress)
                                    .progressViewStyle(LinearProgressViewStyle(tint: isCalibrationReady ? .green : .blue))
                                    .animation(.easeInOut(duration: 0.3), value: calibrationProgress)
                                
                                // Progress percentage
                                Text("\(Int(calibrationProgress * 100))% Complete")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(isCalibrationReady ? .green : .blue)
                            }
                            
                            // Real-time stats
                            HStack(spacing: 20) {
                                // Steps count
                                VStack(spacing: 4) {
                                    Image(systemName: "figure.walk")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                    Text("\(imuState.calibrationStepCount)")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    Text("Steps")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                                
                                // Distance covered
                                VStack(spacing: 4) {
                                    Image(systemName: "ruler")
                                        .font(.title2)
                                        .foregroundColor(.orange)
                                    Text(String(format: "%.1f", estimatedDistanceCovered))
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    Text("Meters")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                                
                                // Remaining distance
                                VStack(spacing: 4) {
                                    Image(systemName: "flag.checkered")
                                        .font(.title2)
                                        .foregroundColor(isCalibrationReady ? .green : .gray)
                                    Text(String(format: "%.1f", remainingDistance))
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(isCalibrationReady ? .green : .primary)
                                    Text("To Go")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background((isCalibrationReady ? Color.green : Color.gray).opacity(0.1))
                                .cornerRadius(8)
                            }
                            
                            // Status message
                            if isCalibrationReady {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("20 meters reached! Calibration will complete automatically.")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                            } else {
                                HStack {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.blue)
                                    Text("Keep walking until you reach 20 meters...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } else {
                        // Calibration instructions (when not calibrating)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("How to calibrate:")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                CalibrationStep(number: 1, text: "Tap 'Start Calibration'")
                                CalibrationStep(number: 2, text: "Walk - the app tracks your progress")
                                CalibrationStep(number: 3, text: "Calibration auto-completes after 20 meters")
                            }
                            
                            // Note about auto-tracking
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.yellow)
                                Text("No need to measure beforehand - the app shows your progress in real-time!")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Calibration buttons
                    HStack(spacing: 12) {
                        if imuState.isCalibrating {
                            // Cancel button
                            Button(action: onStopCalibration) {
                                Label("Cancel", systemImage: "xmark")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.red.opacity(0.1))
                                    .foregroundColor(.red)
                                    .cornerRadius(8)
                            }
                            
                            // Complete button (highlighted when ready)
                            Button(action: onCompleteCalibration) {
                                Label("Complete", systemImage: "checkmark")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(isCalibrationReady ? Color.green : Color.green.opacity(0.6))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .disabled(imuState.calibrationStepCount < 5)
                            .animation(.easeInOut, value: isCalibrationReady)
                        } else {
                            // Start button
                            Button(action: onStartCalibration) {
                                Label(imuState.isStepCalibrationValid ? "Recalibrate" : "Start Calibration",
                                      systemImage: "figure.walk")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
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
                    position: Position(),
                    stepCount: 0,
                    isCalibrated: false,
                    accelerationMagnitude: 0,
                    isMoving: false,
                    currentStepLength: 0.65,
                    filterQuality: "Initializing",
                    beta: 0.600,
                    isStepCalibrationValid: false,
                    isCalibrating: false,
                    calibrationStepCount: 0,
                    bearing: 0
                ),
                onStartCalibration: {},
                onCompleteCalibration: {},
                onStopCalibration: {}
            )
            
            // Calibrating state (in progress)
            StepCalibrationCard(
                imuState: IMUState(
                    position: Position(),
                    stepCount: 15,
                    isCalibrated: false,
                    accelerationMagnitude: 0.5,
                    isMoving: true,
                    currentStepLength: 0.72,
                    filterQuality: "Good",
                    beta: 0.600,
                    isStepCalibrationValid: false,
                    isCalibrating: true,
                    calibrationStepCount: 18,
                    bearing: 45
                ),
                onStartCalibration: {},
                onCompleteCalibration: {},
                onStopCalibration: {}
            )
            
            // Calibrating state (ready to complete - 20m reached)
            StepCalibrationCard(
                imuState: IMUState(
                    position: Position(),
                    stepCount: 31,
                    isCalibrated: false,
                    accelerationMagnitude: 0.5,
                    isMoving: true,
                    currentStepLength: 0.75,
                    filterQuality: "Good",
                    beta: 0.600,
                    isStepCalibrationValid: false,
                    isCalibrating: true,
                    calibrationStepCount: 31,
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
