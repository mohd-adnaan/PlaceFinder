import Foundation
import ARKit

class ARMappingManager: NSObject, ObservableObject, ARSessionDelegate {
    @Published var isMapping = false
    @Published var mappingStatus: ARFrame.WorldMappingStatus = .notAvailable
    @Published var savedMapURL: URL?
    
    let session = ARSession()
    
    override init() {
        super.init()
        session.delegate = self
    }
    
    func startMapping() {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isMapping = true
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
    
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        DispatchQueue.main.async {
            self.mappingStatus = frame.worldMappingStatus
        }
    }
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
}
