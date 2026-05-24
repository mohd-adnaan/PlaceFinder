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
        
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingOverlay.session = session
        coachingOverlay.goal = .tracking
        arView.addSubview(coachingOverlay)
        
        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct ARMappingView: View {
    @StateObject private var mappingManager = ARMappingManager()
    @State private var newPOIName: String = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            ARViewContainer(session: mappingManager.session)
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    mappingManager.startCameraFeed()
                }
                .onDisappear {
                    mappingManager.stopMapping()
                }

            VStack {
                // Top HUD
                VStack(spacing: 8) {
                    Text(statusText)
                        .font(.headline)
                        .foregroundColor(mappingManager.isLocalized ? .green : .white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(20)

                    if !mappingManager.currentPositionText.isEmpty {
                        Text(mappingManager.currentPositionText)
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                            .padding(12)
                            .background(Color.black.opacity(0.8))
                            .foregroundColor(.cyan)
                            .cornerRadius(12)
                    }

                    if let savedURL = mappingManager.savedMapURL {
                        Text("Saved: \(savedURL.lastPathComponent)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .padding(.top, 4)
                    }
                }
                .padding(.top, 50)

                Spacer()

                // Bottom Controls
                VStack(spacing: 16) {
                    if !mappingManager.isMapping && !mappingManager.isRelocalizing {
                        Button(action: { mappingManager.startMapping() }) {
                            Text("Start New Mapping")
                                .bold().frame(maxWidth: .infinity).padding()
                                .background(Color.blue).foregroundColor(.white).cornerRadius(14)
                        }
                        Button(action: { mappingManager.loadMapAndRelocalize() }) {
                            Text("Load Map & Relocalize")
                                .bold().frame(maxWidth: .infinity).padding()
                                .background(Color.orange).foregroundColor(.white).cornerRadius(14)
                        }
                    } else {
                        // Drop POI Bar
                        if mappingManager.isLocalized || mappingManager.isMapping {
                            if !mappingManager.anchorsList.isEmpty {
                                Text("Stored POIs: \(mappingManager.anchorsList.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(1)
                                    .padding(.horizontal)
                            }

                            HStack {
                                TextField("Enter POI Name", text: $newPOIName)
                                    .padding(12)
                                    .background(Color.white)
                                    .cornerRadius(8)
                                    .foregroundColor(.black)

                                Button(action: {
                                    if !newPOIName.isEmpty {
                                        mappingManager.addPOIAnchor(name: newPOIName)
                                        newPOIName = ""
                                    }
                                }) {
                                    Text("Drop POI")
                                        .bold().padding(12)
                                        .background(Color.purple).foregroundColor(.white).cornerRadius(8)
                                }
                            }
                        }

                        // Action Buttons
                        HStack(spacing: 16) {
                            Button(action: { mappingManager.saveMap() }) {
                                Text(mappingManager.isRelocalizing ? "Save Expanded Map" : "Save Map")
                                    .bold().frame(maxWidth: .infinity).padding()
                                    .background(Color.green).foregroundColor(.white).cornerRadius(14)
                            }

                            Button(action: { mappingManager.stopMapping() }) {
                                Text("Stop")
                                    .bold().frame(maxWidth: .infinity).padding()
                                    .background(Color.red).foregroundColor(.white).cornerRadius(14)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .background(
                    LinearGradient(gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.9)]), startPoint: .top, endPoint: .bottom)
                        .edgesIgnoringSafeArea(.bottom)
                )
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
