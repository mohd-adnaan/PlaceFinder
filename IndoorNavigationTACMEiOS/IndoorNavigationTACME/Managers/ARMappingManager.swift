import Foundation
import ARKit

class ARMappingManager: NSObject, ObservableObject, ARSessionDelegate {
    @Published var isMapping = false
    @Published var mappingStatus: ARFrame.WorldMappingStatus = .notAvailable
    @Published var savedMapURL: URL?
    @Published var isRelocalizing = false
    @Published var isLocalized = false
    @Published var currentPositionText: String = ""
    
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
        
        let config = ARWorldTrackingConfiguration()
        config.initialWorldMap = map
        config.planeDetection = [.horizontal, .vertical]
        config.worldAlignment = .gravityAndHeading
        
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isRelocalizing = true
        isMapping = false
    }
    
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        DispatchQueue.main.async {
            self.mappingStatus = frame.worldMappingStatus
            
            if self.isLocalized {
                let transform = frame.camera.transform
                let x = transform.columns.3.x
                let z = transform.columns.3.z
                let yaw = frame.camera.eulerAngles.y * 180 / .pi
                
                self.currentPositionText = String(format: "Position: (X: %.2f, Z: %.2f)\nHeading: %.0f°", x, z, yaw)
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
