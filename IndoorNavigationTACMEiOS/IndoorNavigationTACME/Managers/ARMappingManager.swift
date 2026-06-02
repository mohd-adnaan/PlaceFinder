import Foundation
@preconcurrency import ARKit

enum ARMappingSessionMode {
    case idle
    case mapping
    case relocalizing
}

final class ARMappingManager: NSObject, ObservableObject, ARSessionDelegate, @unchecked Sendable {
    @Published var isMapping = false
    @Published var mappingStatus: ARFrame.WorldMappingStatus = .notAvailable
    @Published var savedMapURL: URL?
    @Published var isRelocalizing = false
    @Published var isLocalized = false
    @Published var isSavingMap = false
    @Published var sessionMode: ARMappingSessionMode = .idle
    @Published var currentPositionText: String = ""
    @Published var statusMessage: String?
    @Published var closestPOI: String?
    @Published var poiMatchStatusText: String?
    @Published var anchorsList: [String] = []
    @Published var mapPOIs: [String: simd_float3] = [:]
    
    let session = ARSession()
    private let sessionDelegateQueue = DispatchQueue(label: "placefinder.arkit.mapping.session", qos: .userInitiated)
    private let poiRecordsQueue = DispatchQueue(label: "placefinder.arkit.mapping.poi-records", attributes: .concurrent)
    private var poiAnchorsByName: [String: ARAnchor] = [:]
    private var poiRecords: [POIRecord] = []
    private var lastUpdateTime: TimeInterval = 0
    private let frameUpdateInterval: TimeInterval = 0.15
    private let nearbySnapDistance: Float = 0.55
    private let maxPOIRecognitionDistance: Float = 24.0
    private let verticalTolerance: Float = 2.0
    private let minimumPOIMatchConfidence: Float = 0.48
    private let ambiguousScoreGap: Float = 0.16
    
    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = sessionDelegateQueue
    }
    
    func startCameraFeed() {
        // Kept for compatibility with older call sites. The AR session is intentionally idle
        // until the user explicitly starts mapping or relocalization.
        stopMapping()
    }
    
    func startMapping() {
        guard ARWorldTrackingConfiguration.isSupported else {
            statusMessage = "AR world tracking is not supported on this device."
            return
        }

        let config = makeWorldTrackingConfiguration()
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        lastUpdateTime = 0
        isMapping = true
        isRelocalizing = false
        isLocalized = false
        sessionMode = .mapping
        mappingStatus = .notAvailable
        currentPositionText = ""
        closestPOI = nil
        poiMatchStatusText = nil
        anchorsList.removeAll()
        mapPOIs.removeAll()
        poiAnchorsByName.removeAll()
        replacePOIRecords(with: [])
        statusMessage = nil
    }
    
    func stopMapping() {
        session.pause()
        isMapping = false
        isRelocalizing = false
        isLocalized = false
        isSavingMap = false
        sessionMode = .idle
        mappingStatus = .notAvailable
        currentPositionText = ""
        closestPOI = nil
        poiMatchStatusText = nil
    }
    
    func saveMap() {
        isSavingMap = true
        session.getCurrentWorldMap { worldMap, error in
            guard let map = worldMap else {
                DispatchQueue.main.async {
                    self.isSavingMap = false
                    self.statusMessage = error?.localizedDescription ?? "Could not read the current AR map."
                }
                return
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                    let url = self.getDocumentsDirectory().appendingPathComponent("BuildingMap.arexperience")
                    try data.write(to: url)
                    
                    DispatchQueue.main.async {
                        self.isSavingMap = false
                        self.savedMapURL = url
                        self.statusMessage = "Map saved as \(url.lastPathComponent)."
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isSavingMap = false
                        self.statusMessage = "Failed to save map: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    func loadMapAndRelocalize() {
        guard ARWorldTrackingConfiguration.isSupported else {
            statusMessage = "AR world tracking is not supported on this device."
            return
        }

        let url = getDocumentsDirectory().appendingPathComponent("BuildingMap.arexperience")
        statusMessage = "Loading saved map..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = try? Data(contentsOf: url),
                  let map = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
                DispatchQueue.main.async {
                    self.statusMessage = "No saved map found."
                }
                return
            }

            let loadedPOIs = self.deduplicatedPOIs(self.extractPOIs(from: map))
            
            DispatchQueue.main.async {
                self.anchorsList = loadedPOIs.map(\.name)
                self.mapPOIs = Dictionary(uniqueKeysWithValues: loadedPOIs.map { ($0.name, $0.position) })
                self.poiAnchorsByName = Dictionary(uniqueKeysWithValues: loadedPOIs.map { ($0.name, $0.anchor) })
                self.replacePOIRecords(with: loadedPOIs.map { POIRecord(name: $0.name, position: $0.position) })
                self.isRelocalizing = true
                self.isMapping = false
                self.isLocalized = false
                self.sessionMode = .relocalizing
                self.mappingStatus = .notAvailable
                self.currentPositionText = ""
                self.closestPOI = nil
                self.poiMatchStatusText = nil
                self.lastUpdateTime = 0
                self.statusMessage = loadedPOIs.isEmpty
                    ? "Map loaded. No POIs are pinned yet."
                    : "Map loaded with \(loadedPOIs.count) POIs."
                
                let config = self.makeWorldTrackingConfiguration(initialWorldMap: map)
                self.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            }
        }
    }
    
    func addPOIAnchor(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard isMapping || isLocalized else {
            statusMessage = "Start mapping or relocalize before pinning a POI."
            return
        }
        guard let currentTransform = session.currentFrame?.camera.transform else {
            statusMessage = "Camera pose is not ready yet."
            return
        }

        if let existingAnchor = poiAnchorsByName[trimmedName] {
            session.remove(anchor: existingAnchor)
        }

        let anchor = ARAnchor(name: trimmedName, transform: currentTransform)
        session.add(anchor: anchor)

        let anchorPos = simd_make_float3(currentTransform.columns.3.x, currentTransform.columns.3.y, currentTransform.columns.3.z)

        if !anchorsList.contains(trimmedName) {
            anchorsList.append(trimmedName)
        }
        mapPOIs[trimmedName] = anchorPos
        poiAnchorsByName[trimmedName] = anchor
        replacePOIRecords(with: mapPOIs.map { POIRecord(name: $0.key, position: $0.value) })
        statusMessage = "Pinned \(trimmedName)."
    }

    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let currentTime = frame.timestamp
        if currentTime - lastUpdateTime < frameUpdateInterval { return }
        lastUpdateTime = currentTime
        
        let mappingStatus = frame.worldMappingStatus
        let transform = frame.camera.transform
        let yaw = frame.camera.eulerAngles.y * 180 / .pi
        let poiMatchResult = bestPOIMatch(cameraTransform: transform)
        
        let x = transform.columns.3.x
        let z = transform.columns.3.z

        DispatchQueue.main.async {
            self.mappingStatus = mappingStatus
            
            if self.isLocalized {
                if let match = poiMatchResult.match {
                    self.closestPOI = match.name
                    self.poiMatchStatusText = String(format: "Confidence %.0f%%", match.confidence * 100)
                    self.currentPositionText = String(
                        format: "X %.1f  Z %.1f  HDG %.0f°\nPOI %@  %.1fm  %.0f°",
                        x,
                        z,
                        yaw,
                        match.name,
                        match.distance,
                        match.angleDegrees
                    )
                } else if poiMatchResult.isAmbiguous {
                    self.closestPOI = nil
                    self.poiMatchStatusText = "Ambiguous view"
                    self.currentPositionText = String(format: "X %.1f  Z %.1f  HDG %.0f°\nAlign camera with one POI", x, z, yaw)
                } else {
                    self.closestPOI = nil
                    self.poiMatchStatusText = nil
                    self.currentPositionText = String(format: "X %.1f  Z %.1f  HDG %.0f°\nNo POI in view", x, z, yaw)
                }
            } else if self.isMapping {
                self.currentPositionText = String(format: "X %.1f  Z %.1f  HDG %.0f°", x, z, yaw)
                self.poiMatchStatusText = nil
            } else {
                self.currentPositionText = ""
                self.poiMatchStatusText = nil
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
                        self.statusMessage = "Localized against saved map."
                    }
                default:
                    if self.isLocalized {
                        self.isLocalized = false
                        self.closestPOI = nil
                        self.poiMatchStatusText = nil
                        self.statusMessage = "Tracking limited. Hold the camera steady."
                    }
                }
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.statusMessage = error.localizedDescription
            self.isMapping = false
            self.isRelocalizing = false
            self.isLocalized = false
            self.sessionMode = .idle
            self.closestPOI = nil
            self.poiMatchStatusText = nil
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async {
            self.statusMessage = "AR session interrupted."
            self.isLocalized = false
            self.closestPOI = nil
            self.poiMatchStatusText = nil
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async {
            if self.sessionMode != .idle {
                self.statusMessage = "Restart the AR session to recover tracking."
            }
        }
    }
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    private func makeWorldTrackingConfiguration(initialWorldMap: ARWorldMap? = nil) -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.initialWorldMap = initialWorldMap
        config.worldAlignment = .gravityAndHeading
        config.planeDetection = []
        config.environmentTexturing = .none
        config.isLightEstimationEnabled = false
        config.providesAudioData = false
        config.frameSemantics = []
        applyEfficientVideoFormat(to: config)
        return config
    }

    private func applyEfficientVideoFormat(to config: ARWorldTrackingConfiguration) {
        let thirtyFPSFormats = ARWorldTrackingConfiguration.supportedVideoFormats
            .filter { $0.framesPerSecond <= 30 }

        guard !thirtyFPSFormats.isEmpty else {
            return
        }

        let minimumPixels: CGFloat = 1280 * 720
        let viableFormats = thirtyFPSFormats.filter { pixelCount(for: $0) >= minimumPixels }
        let formatPool = viableFormats.isEmpty ? thirtyFPSFormats : viableFormats

        guard let format = formatPool.min(by: { pixelCount(for: $0) < pixelCount(for: $1) }) else { return }
        config.videoFormat = format
    }

    private func pixelCount(for format: ARConfiguration.VideoFormat) -> CGFloat {
        format.imageResolution.width * format.imageResolution.height
    }

    private func extractPOIs(from map: ARWorldMap) -> [(name: String, position: simd_float3, anchor: ARAnchor)] {
        map.anchors.compactMap { anchor in
            guard type(of: anchor) == ARAnchor.self,
                  let name = anchor.name,
                  !name.isEmpty else {
                return nil
            }

            let position = simd_make_float3(
                anchor.transform.columns.3.x,
                anchor.transform.columns.3.y,
                anchor.transform.columns.3.z
            )
            return (name: name, position: position, anchor: anchor)
        }
    }

    private func deduplicatedPOIs(_ pois: [(name: String, position: simd_float3, anchor: ARAnchor)]) -> [(name: String, position: simd_float3, anchor: ARAnchor)] {
        var latestByName: [String: (position: simd_float3, anchor: ARAnchor)] = [:]
        var orderedNames: [String] = []

        for poi in pois {
            if latestByName[poi.name] == nil {
                orderedNames.append(poi.name)
            }
            latestByName[poi.name] = (poi.position, poi.anchor)
        }

        return orderedNames.compactMap { name in
            guard let poi = latestByName[name] else { return nil }
            return (name: name, position: poi.position, anchor: poi.anchor)
        }
    }

    private struct POIRecord {
        let name: String
        let position: simd_float3
    }

    private struct POIMatch {
        let name: String
        let distance: Float
        let angleDegrees: Float
        let confidence: Float
        let score: Float
    }

    private struct POIMatchResult {
        let match: POIMatch?
        let isAmbiguous: Bool
    }

    private func replacePOIRecords(with records: [POIRecord]) {
        poiRecordsQueue.async(flags: .barrier) {
            self.poiRecords = records
        }
    }

    private func currentPOIRecords() -> [POIRecord] {
        poiRecordsQueue.sync {
            poiRecords
        }
    }

    private func bestPOIMatch(cameraTransform: simd_float4x4) -> POIMatchResult {
        let records = currentPOIRecords()
        guard !records.isEmpty else { return POIMatchResult(match: nil, isAmbiguous: false) }

        let cameraPosition = simd_make_float3(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        let cameraForward = horizontalNormalized(
            simd_make_float3(
                -cameraTransform.columns.2.x,
                -cameraTransform.columns.2.y,
                -cameraTransform.columns.2.z
            )
        )

        guard simd_length(cameraForward) > 0 else {
            return POIMatchResult(match: nil, isAmbiguous: false)
        }

        var candidates: [POIMatch] = []

        for poi in records {
            let offset = poi.position - cameraPosition
            let distance = simd_length(offset)

            if distance <= nearbySnapDistance {
                candidates.append(POIMatch(name: poi.name, distance: distance, angleDegrees: 0, confidence: 1, score: distance * 0.12))
                continue
            }

            let horizontalOffset = simd_make_float3(offset.x, 0, offset.z)
            let horizontalDistance = simd_length(horizontalOffset)
            guard horizontalDistance > 0.05,
                  horizontalDistance <= maxPOIRecognitionDistance,
                  abs(offset.y) <= verticalTolerance else {
                continue
            }

            let directionToPOI = horizontalOffset / horizontalDistance
            let dot = max(-1, min(1, simd_dot(cameraForward, directionToPOI)))
            let angleDegrees = acos(dot) * 180 / Float.pi
            let coneDegrees = coneLimit(forDistance: horizontalDistance)
            guard angleDegrees <= coneDegrees else { continue }

            let crossTrackError = horizontalDistance * sin(angleDegrees * Float.pi / 180)
            let lateralTolerance = lateralTolerance(forDistance: horizontalDistance)
            guard crossTrackError <= lateralTolerance else { continue }

            let angleScore = angleDegrees / coneDegrees
            let lateralScore = crossTrackError / lateralTolerance
            let distanceScore = min(horizontalDistance / maxPOIRecognitionDistance, 1)
            let score = lateralScore * 0.56 + angleScore * 0.32 + distanceScore * 0.12
            let confidence = max(0, min(1, 1 - score))
            guard confidence >= minimumPOIMatchConfidence else { continue }

            candidates.append(POIMatch(name: poi.name, distance: distance, angleDegrees: angleDegrees, confidence: confidence, score: score))
        }

        let sortedCandidates = candidates.sorted { $0.score < $1.score }
        guard let bestMatch = sortedCandidates.first else {
            return POIMatchResult(match: nil, isAmbiguous: false)
        }

        if let secondMatch = sortedCandidates.dropFirst().first,
           bestMatch.distance > nearbySnapDistance,
           secondMatch.score - bestMatch.score < ambiguousScoreGap,
           simd_distance(position(for: bestMatch, in: records), position(for: secondMatch, in: records)) > nearbySnapDistance {
            return POIMatchResult(match: nil, isAmbiguous: true)
        }

        return POIMatchResult(match: bestMatch, isAmbiguous: false)
    }

    private func horizontalNormalized(_ vector: simd_float3) -> simd_float3 {
        let horizontal = simd_make_float3(vector.x, 0, vector.z)
        let length = simd_length(horizontal)
        guard length > 0 else { return simd_make_float3(0, 0, 0) }
        return horizontal / length
    }

    private func coneLimit(forDistance distance: Float) -> Float {
        max(8, min(32, 36 - distance * 1.35))
    }

    private func lateralTolerance(forDistance distance: Float) -> Float {
        max(0.45, min(1.65, 0.28 + distance * 0.09))
    }

    private func position(for match: POIMatch, in records: [POIRecord]) -> simd_float3 {
        records.first(where: { $0.name == match.name })?.position ?? simd_make_float3(0, 0, 0)
    }
}
