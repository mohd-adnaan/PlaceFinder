import SwiftUI
import ARKit

// A simple ARView wrapper for SwiftUI just to show the camera feed while mapping
struct ARViewContainer: UIViewRepresentable {
    var session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.session = session
        // Show feature points so the developer knows what ARKit sees
        arView.debugOptions = [.showFeaturePoints]
        arView.autoenablesDefaultLighting = true
        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct ARMappingView: View {
    @StateObject private var mappingManager = ARMappingManager()

    var body: some View {
        ZStack(alignment: .bottom) {
            ARViewContainer(session: mappingManager.session)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 20) {
                // Status Indicator
                Text(statusText)
                    .font(.headline)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(10)

                if !mappingManager.currentPositionText.isEmpty {
                    Text(mappingManager.currentPositionText)
                        .font(.body)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.cyan)
                        .cornerRadius(10)
                }

                if let savedURL = mappingManager.savedMapURL {
                    Text("Saved to: \(savedURL.lastPathComponent)")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                }

                HStack(spacing: 20) {
                    if !mappingManager.isMapping && !mappingManager.isRelocalizing {
                        VStack(spacing: 15) {
                            Button(action: {
                                mappingManager.startMapping()
                            }) {
                                Text("Start Mapping")
                                    .bold()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }

                            Button(action: {
                                mappingManager.loadMapAndRelocalize()
                            }) {
                                Text("Load Map & Relocalize")
                                    .bold()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        }
                    } else if mappingManager.isMapping {
                        Button(action: {
                            mappingManager.saveMap()
                        }) {
                            Text("Save Map")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }

                        Button(action: {
                            mappingManager.stopMapping()
                        }) {
                            Text("Stop")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    } else if mappingManager.isRelocalizing {
                        Button(action: {
                            mappingManager.stopMapping() // Stops the session
                        }) {
                            Text("Stop Relocalizing")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
        }
    }

    private var statusText: String {
        if mappingManager.isRelocalizing {
            if mappingManager.isLocalized {
                return "✅ Localized!"
            } else {
                return "🔍 Looking for map features..."
            }
        }

        if !mappingManager.isMapping {
            return "Ready"
        }

        switch mappingManager.mappingStatus {
        case .notAvailable: return "Not Available"
        case .limited: return "Limited - Move around to scan"
        case .extending: return "Extending Map..."
        case .mapped: return "Mapped - Ready to Save!"
        @unknown default: return "Unknown"
        }
    }
}
