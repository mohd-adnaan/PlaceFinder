import Foundation
import ARKit
import Combine

class ARLocalizationManager: NSObject, ObservableObject, ARSessionDelegate {
    @Published var isRelocalizing = false
    @Published var isLocalized = false
    @Published var detectedLocationText: String = ""
    @Published var currentPOI: String?

    let session = ARSession()
    private var mapPOIs: [String: simd_float3] = [:]

    // Callback to pass the localized string back to caller when successful
    var onLocationFound: ((String) -> Void)?

    override init() {
        super.init()
        session.delegate = self
    }

    func startLocalization(onFound: @escaping (String) -> Void) {
        self.onLocationFound = onFound
        self.currentPOI = nil

        let url = getDocumentsDirectory().appendingPathComponent("BuildingMap.arexperience")
        guard let data = try? Data(contentsOf: url),
              let map = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
            print("❌ ARLocalizationManager: No map found at \(url.path)")
            onFound("") // Empty means we couldn't load map
            return
        }

        DispatchQueue.main.async {
            self.mapPOIs.removeAll()
            for anchor in map.anchors {
                if let name = anchor.name {
                    self.mapPOIs[name] = simd_make_float3(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
                }
            }
            self.isRelocalizing = true
            self.isLocalized = false
        }

        let config = ARWorldTrackingConfiguration()
        config.initialWorldMap = map
        config.planeDetection = [.horizontal, .vertical]
        config.worldAlignment = .gravityAndHeading

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }

        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stopLocalization() {
        session.pause()
        DispatchQueue.main.async {
            self.isRelocalizing = false
            self.isLocalized = false
        }
    }

    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if isLocalized {
            let cameraTransform = frame.camera.transform
            let cameraPos = simd_make_float3(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
            let cameraForward = simd_normalize(simd_make_float3(-cameraTransform.columns.2.x, -cameraTransform.columns.2.y, -cameraTransform.columns.2.z))

            var bestScore: Float = Float.infinity
            var exactName: String? = nil

            for (name, pos) in mapPOIs {
                let toPOI = pos - cameraPos
                let distance = simd_length(toPOI)

                if distance < 0.1 {
                    if distance < bestScore {
                        bestScore = distance
                        exactName = name
                    }
                    continue
                }

                let dirToPOI = toPOI / distance
                let dotProduct = simd_dot(cameraForward, dirToPOI)

                if dotProduct > 0.8 {
                    let score = distance
                    if score < bestScore {
                        bestScore = score
                        exactName = name
                    }
                }
            }

            if let foundPOI = exactName {
                DispatchQueue.main.async {
                    if self.currentPOI != foundPOI {
                        self.currentPOI = foundPOI
                        self.onLocationFound?(foundPOI)
                        // Stop the session to save battery once we found where they are!
                        self.stopLocalization()
                    }
                }
            }
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        DispatchQueue.main.async {
            if self.isRelocalizing {
                switch camera.trackingState {
                case .normal:
                    if !self.isLocalized {
                        self.isLocalized = true
                        print("✅ ARLocalizationManager: Successfully relocalized against the map!")
                    }
                default:
                    if self.isLocalized {
                        self.isLocalized = false
                        print("⚠️ ARLocalizationManager: Lost localization.")
                    }
                }
            }
        }
    }

    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
}
