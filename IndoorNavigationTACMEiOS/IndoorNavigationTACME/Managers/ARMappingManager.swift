import Foundation
import ARKit

class ARMappingManager: NSObject, ObservableObject, ARSessionDelegate {
    @Published var isMapping = false
    @Published var mappingStatus: ARFrame.WorldMappingStatus = .notAvailable
    @Published var savedMapURL: URL?
    @Published var isRelocalizing = false
    @Published var isLocalized = false
    @Published var currentPositionText: String = ""
    @Published var closestPOI: String?
    @Published var anchorsList: [String] = []
    @Published var mapPOIs: [String: simd_float3] = [:]
    
    let session = ARSession()
    
    override init() {
        super.init()
        session.delegate = self
    }
    
    func startMapping() {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        config.worldAlignment = .gravityAndHeading

        // Ensure 3D depth and geometry mapping without LiDAR is as robust as possible.
        // If LiDAR is available, it uses sceneReconstruction, but for non-Pro iPhones
        // it relies heavily on feature points and plane detection which we enabled above.
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }

        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isMapping = true
        isRelocalizing = false
    }
    
    func stopMapping() {
        session.pause()
        isMapping = false
    }
    
    func saveMap() {
        session.getCurrentWorldMap { worldMap, error in
            guard let map = worldMap else {
                print("Error getting world map: \(String(describing: error))")
                return
            }
            
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                let url = self.getDocumentsDirectory().appendingPathComponent("BuildingMap.arexperience")
                try data.write(to: url)
                
                DispatchQueue.main.async {
                    self.savedMapURL = url
                    print("✅ Map successfully saved to: \(url.path)")
                }
            } catch {
                print("❌ Failed to save map: \(error)")
            }
        }
    }
    
    func loadMapAndRelocalize() {
        let url = getDocumentsDirectory().appendingPathComponent("BuildingMap.arexperience")
        guard let data = try? Data(contentsOf: url),
              let map = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
            print("❌ No map found at \(url.path)")
            return
        }
        
        DispatchQueue.main.async {
            self.anchorsList = map.anchors.compactMap { $0.name }
            self.mapPOIs.removeAll()
            for anchor in map.anchors {
                if let name = anchor.name {
                    self.mapPOIs[name] = simd_make_float3(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
                }
            }
            self.isRelocalizing = true
            self.isMapping = false
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
        isRelocalizing = true
        isMapping = false
    }
    
    func addPOIAnchor(name: String) {
        guard let currentTransform = session.currentFrame?.camera.transform else { return }
        // Create an anchor at the current camera position
        let anchor = ARAnchor(name: name, transform: currentTransform)
        session.add(anchor: anchor)
        
        let anchorPos = simd_make_float3(currentTransform.columns.3.x, currentTransform.columns.3.y, currentTransform.columns.3.z)
        
        DispatchQueue.main.async {
            if !self.anchorsList.contains(name) {
                self.anchorsList.append(name)
            }
            self.mapPOIs[name] = anchorPos
        }
        print("✅ Added POI Anchor: \(name)")
    }
    
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        DispatchQueue.main.async {
            self.mappingStatus = frame.worldMappingStatus
            
            if self.isLocalized {
                let cameraTransform = frame.camera.transform
                let x = cameraTransform.columns.3.x
                let z = cameraTransform.columns.3.z
                let yaw = frame.camera.eulerAngles.y * 180 / .pi
                
                let cameraPos = simd_make_float3(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
                // ARKit camera looks down the negative Z axis
                let cameraForward = simd_normalize(simd_make_float3(-cameraTransform.columns.2.x, -cameraTransform.columns.2.y, -cameraTransform.columns.2.z))

                var bestScore: Float = Float.infinity
                var exactName: String? = nil
                
                for (name, pos) in self.mapPOIs {
                    let toPOI = pos - cameraPos
                    let distance = simd_length(toPOI)

                    if distance < 0.1 { // If we are essentially inside the POI
                        if distance < bestScore {
                            bestScore = distance
                            exactName = name
                        }
                        continue
                    }

                    let dirToPOI = toPOI / distance
                    let dotProduct = simd_dot(cameraForward, dirToPOI)

                    // User is looking in the direction of the POI
                    if dotProduct > 0.8 {
                        // The user has this POI in their view cone.
                        // We score it primarily by distance, so the nearest one they look at wins.
                        let score = distance

                        if score < bestScore {
                            bestScore = score
                            exactName = name
                        }
                    }
                }
                
                self.closestPOI = exactName
                let poiText = exactName != nil ? "\n📍 POI: \(exactName!)" : ""
                self.currentPositionText = String(format: "X: %.1f, Z: %.1f | HDG: %.0f°%@", x, z, yaw, poiText)
            } else {
                self.currentPositionText = ""
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
                        print("✅ Successfully relocalized against the map!")
                    }
                default:
                    if self.isLocalized {
                        self.isLocalized = false
                        print("⚠️ Lost localization.")
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
