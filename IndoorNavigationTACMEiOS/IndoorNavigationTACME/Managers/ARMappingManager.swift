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
    
    func startCameraFeed() {
        let config = ARWorldTrackingConfiguration()
        // Just start the camera so it's not a black screen. 
        // The coaching overlay will take over.
        session.run(config)
    }
    
    func startMapping() {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        config.worldAlignment = .gravityAndHeading
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
            
            // Move heavy archiving and file I/O to a background thread to prevent main thread freezing!
            DispatchQueue.global(qos: .userInitiated).async {
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
    }
    
    func loadMapAndRelocalize() {
        let url = getDocumentsDirectory().appendingPathComponent("BuildingMap.arexperience")
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = try? Data(contentsOf: url),
                  let map = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
                print("❌ No map found at \(url.path)")
                return
            }
            
            DispatchQueue.main.async {
                self.anchorsList.removeAll()
                self.mapPOIs.removeAll()
                print("🗺️ Loading POIs from ARWorldMap...")
                for anchor in map.anchors {
                    // Ignore ARPlaneAnchor and other subclasses; only load our manually dropped ARAnchors
                    if type(of: anchor) == ARAnchor.self, let name = anchor.name {
                        self.anchorsList.append(name)
                        let pos = simd_make_float3(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
                        self.mapPOIs[name] = pos
                        print("   📍 Loaded POI: '\(name)' at X: \(String(format: "%.2f", pos.x)), Y: \(String(format: "%.2f", pos.y)), Z: \(String(format: "%.2f", pos.z))")
                    }
                }
                print("🗺️ Total POIs loaded: \(self.mapPOIs.count)")
                
                self.isRelocalizing = true
                self.isMapping = false
                self.isLocalized = false
                
                let config = ARWorldTrackingConfiguration()
                config.initialWorldMap = map
                config.planeDetection = [.horizontal, .vertical]
                config.worldAlignment = .gravityAndHeading
                
                self.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            }
        }
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

    private var lastUpdateTime: TimeInterval = 0

    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Throttle to 10 FPS to completely eliminate main thread flooding and lag!
        let currentTime = frame.timestamp
        if currentTime - lastUpdateTime < 0.1 { return }
        lastUpdateTime = currentTime
        
        // Extract values OUTSIDE the main thread block
        let mappingStatus = frame.worldMappingStatus
        let transform = frame.camera.transform
        let yaw = frame.camera.eulerAngles.y * 180 / .pi
        
        let x = transform.columns.3.x
        let y = transform.columns.3.y
        let z = transform.columns.3.z
        let cameraPos = simd_make_float3(x, y, z)

        DispatchQueue.main.async {
            self.mappingStatus = mappingStatus
            
            if self.isLocalized {
                // Find closest POI directly from our permanent map database
                var minDistance: Float = Float.infinity
                var nearestName: String? = nil

                for (name, pos) in self.mapPOIs {
                    let distance = simd_distance(cameraPos, pos)
                    if distance < minDistance {
                        minDistance = distance
                        nearestName = name
                    }
                }

                self.closestPOI = nearestName
                let poiText = nearestName != nil ? "\n📍 Nearest: \(nearestName!) (\(String(format: "%.1f", minDistance))m)" : ""
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
