import SwiftUI

struct SemanticNavigationPanel: View {
    @ObservedObject var navigator: SemanticRouteNavigator
    @Binding var mapName: String

    let arStatusText: String
    let activeARMapName: String?
    let closestPOI: String?
    let savedARMaps: [ARStoredMapSummary]
    let selectedARMapID: String?
    let canUseARPose: Bool
    let isARSessionActive: Bool
    let isSavingARMap: Bool
    let selectARMap: (String?) -> Void
    let startARMapping: () -> Void
    let loadARMap: () -> Void
    let saveARMap: () -> Void
    let stopARSession: () -> Void
    let beginWalkthrough: (String) -> Void
    let captureStart: (String) -> Void
    let captureTurn: (SemanticTurnHint) -> Void
    let captureLandmark: (String, SemanticRouteSide, String, Bool) -> Void
    let saveWalkthrough: () -> Void
    let startNavigation: (String) -> Void
    let snapToRoute: () -> Void

    @State private var mode: RoutePanelMode = .map
    @State private var startName = ""
    @State private var landmarkName = ""
    @State private var destinationName = ""
    @State private var landmarkNote = ""
    @State private var selectedSide: SemanticRouteSide = .left
    @State private var targetName = ""
    @State private var showRouteReview = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            modeSwitch

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if mode == .map {
                        mappingFlow
                    } else {
                        guidanceFlow
                    }
                }
                .padding(.bottom, 2)
            }
            .frame(maxHeight: 500)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.76))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            syncStartName()
            syncTargetName()
        }
        .onChange(of: closestPOI) { _, _ in syncStartName() }
        .onChange(of: navigator.availableTargets) { _, _ in syncTargetName() }
        .onChange(of: navigator.phase) { _, phase in
            if phase == .navigating || phase == .recovering || phase == .arrived {
                mode = .guide
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label("AR Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)

            Spacer()

            statusPill(navigator.phase.displayName, color: phaseColor)
        }
    }

    private var modeSwitch: some View {
        HStack(spacing: 8) {
            modeButton(.map, title: "Map", systemImage: "map")
            modeButton(.guide, title: "Guide", systemImage: "figure.walk.motion")
        }
        .padding(4)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func modeButton(_ value: RoutePanelMode, title: String, systemImage: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                mode = value
            }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
        }
        .foregroundColor(.white)
        .background(mode == value ? Color.routeTeal : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("\(title) mode")
    }

    private var mappingFlow: some View {
        VStack(alignment: .leading, spacing: 14) {
            arMapStatus

            if navigator.phase == .mapping {
                activeMappingFlow
            } else {
                startMappingFlow
            }
        }
    }

    private var startMappingFlow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create an on-device route by walking from Point A to the target.")
                .routeCaption()

            TextField("Route map name", text: $mapName)
                .routeTextField()

            Button {
                beginWalkthrough(mapName)
                syncStartName(force: true)
            } label: {
                Label("Start Route Mapping", systemImage: "figure.walk")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SemanticRouteButtonStyle(prominence: .primary))

            if !savedARMaps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Load ARWorldMap for relocalization")
                        .routeEyebrow()

                    Picker("Saved AR map", selection: selectedMapBinding) {
                        ForEach(savedARMaps) { map in
                            Text(mapLabel(for: map)).tag(map.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    .routePickerFrame()

                    Button {
                        loadARMap()
                    } label: {
                        Label("Load Selected AR Map", systemImage: "location.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SemanticRouteButtonStyle(prominence: .secondary))
                }
            }
        }
    }

    private var activeMappingFlow: some View {
        VStack(alignment: .leading, spacing: 14) {
            routeProgress

            if navigator.capturedPointCount == 0 {
                pointASection
            } else {
                walkingSection
                landmarkSection
                destinationSection
                reviewSection
                saveSection
            }
        }
    }

    private var pointASection: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepHeader("1", title: "Point A", detail: "Use the detected POI if it is correct, or type the actual start.")

            if let closestPOI, !closestPOI.isEmpty {
                Label("Detected: \(closestPOI)", systemImage: "location.viewfinder")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.86))
            }

            TextField("Start label", text: $startName)
                .routeTextField()

            Button {
                captureStart(startName)
                if startName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    startName = closestPOI ?? "Start"
                }
            } label: {
                Label("Mark Point A", systemImage: "mappin.and.ellipse")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SemanticRouteButtonStyle(prominence: .primary))
            .disabled(!canUseARPose)
        }
        .routeSection()
    }

    private var walkingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepHeader("2", title: "Walk the route", detail: "Distance is measured live. Mark only real turns and the final target.")

            HStack(spacing: 8) {
                turnButton(.left, systemImage: "arrow.turn.up.left")
                turnButton(.right, systemImage: "arrow.turn.up.right")
                turnButton(.straight, systemImage: "arrow.up")
                turnButton(.corner, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            }
        }
        .routeSection()
    }

    private var landmarkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepHeader("3", title: "Landmarks on the way", detail: "Capture shelves, objects, or recovery cues with side information.")

            TextField("Landmark or object name", text: $landmarkName)
                .routeTextField()

            HStack(spacing: 8) {
                Picker("Side", selection: $selectedSide) {
                    ForEach(SemanticRouteSide.allCases) { side in
                        Text(side.displayName).tag(side)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .frame(width: 116)
                .routePickerFrame()

                Button {
                    captureLandmark(landmarkName, selectedSide, landmarkNote, false)
                    landmarkName = ""
                    landmarkNote = ""
                } label: {
                    Label("Add Object", systemImage: "tag")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SemanticRouteButtonStyle(prominence: .secondary))
                .disabled(landmarkName.trimmedRouteText.isEmpty || !canUseARPose)
            }

            TextField("Optional note", text: $landmarkNote)
                .routeTextField()
        }
        .routeSection()
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepHeader("4", title: "Point B target", detail: "This closes the final measured segment and becomes the guidance target.")

            TextField("Destination name", text: $destinationName)
                .routeTextField()

            Button {
                captureLandmark(destinationName, selectedSide, landmarkNote, true)
                if targetName.isEmpty {
                    targetName = destinationName
                }
            } label: {
                Label("Set Destination", systemImage: "scope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SemanticRouteButtonStyle(prominence: .primary))
            .disabled(destinationName.trimmedRouteText.isEmpty || !canUseARPose)
        }
        .routeSection()
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showRouteReview.toggle()
                }
            } label: {
                HStack {
                    Label("Route Review", systemImage: "checklist")
                    Spacer()
                    Image(systemName: showRouteReview ? "chevron.up" : "chevron.down")
                }
            }
            .font(.caption.weight(.bold))
            .foregroundColor(.white.opacity(0.9))

            if showRouteReview {
                let lines = navigator.routeReviewLines
                if lines.isEmpty {
                    Text("Mark Point A to start the route review.")
                        .routeCaption()
                } else {
                    ForEach(lines, id: \.self) { line in
                        Label(line, systemImage: "smallcircle.filled.circle")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .routeSection()
    }

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                saveWalkthrough()
            } label: {
                Label(isSavingARMap ? "Saving Route" : "Save Route And AR Map", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SemanticRouteButtonStyle(prominence: .primary))
            .disabled(!navigator.canSaveCapturedMap || isSavingARMap)

            HStack(spacing: 8) {
                Button {
                    navigator.discardCapture()
                } label: {
                    Label("Discard", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SemanticRouteButtonStyle(prominence: .secondary))

                Button {
                    stopARSession()
                } label: {
                    Label("Stop AR", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SemanticRouteButtonStyle(prominence: .secondary))
            }
        }
    }

    private var guidanceFlow: some View {
        VStack(alignment: .leading, spacing: 14) {
            arMapStatus
            guidanceStatus
            savedRoutePicker

            if navigator.availableTargets.isEmpty {
                emptyGuidanceState
            } else {
                Picker("Destination", selection: $targetName) {
                    ForEach(navigator.availableTargets, id: \.self) { target in
                        Text(target).tag(target)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .routePickerFrame()

                HStack(spacing: 8) {
                    Button {
                        startNavigation(targetName)
                    } label: {
                        Label("Guide", systemImage: "figure.walk.motion")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SemanticRouteButtonStyle(prominence: .primary))
                    .disabled(targetName.trimmedRouteText.isEmpty || !canUseARPose || navigator.phase == .mapping)

                    Button {
                        snapToRoute()
                    } label: {
                        Image(systemName: "scope")
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(SemanticIconButtonStyle())
                    .disabled(!canUseARPose)
                    .accessibilityLabel("Snap to mapped route")

                    Button {
                        navigator.stopNavigation()
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(SemanticIconButtonStyle())
                    .accessibilityLabel("Stop guidance")
                }
            }
        }
    }

    @ViewBuilder
    private var savedRoutePicker: some View {
        if !navigator.maps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved on-device route")
                    .routeEyebrow()

                Picker("Saved route", selection: selectedRouteBinding) {
                    ForEach(navigator.maps) { map in
                        Text(routeLabel(for: map)).tag(map.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .routePickerFrame()
            }
        }
    }

    private var emptyGuidanceState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("No saved route target yet", systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.48))

            Text("Map Point A to Point B first. After saving, destinations and objects appear here.")
                .routeCaption()

            Button {
                mode = .map
            } label: {
                Label("Open Mapper", systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SemanticRouteButtonStyle(prominence: .secondary))
        }
    }

    private var arMapStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusPill(arStatusText, color: canUseARPose ? Color.routeTeal : Color.white.opacity(0.55))
                if let activeARMapName {
                    statusPill(activeARMapName, color: Color.white.opacity(0.78))
                }
            }

            if !isARSessionActive, navigator.phase != .mapping {
                Text("Start mapping to create a fresh ARWorldMap, or load a saved AR map before guidance.")
                    .routeCaption()
            }
        }
    }

    private var routeProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(navigator.mappingStageTitle)
                .font(.headline.weight(.bold))
                .foregroundColor(.white)

            Text(navigator.currentInstruction)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                metricPill("Live leg", meters(navigator.currentSegmentDraftMeters))
                metricPill("Route", meters(navigator.capturedDistanceMeters))
                metricPill("Turns", "\(navigator.capturedTurnCount)")
            }

            HStack(spacing: 8) {
                metricPill("Objects", "\(navigator.capturedLandmarkCount)")
                metricPill("Targets", "\(navigator.capturedDestinationCount)")
                metricPill("Quality", navigator.mappingQualityText)
            }
        }
    }

    private var guidanceStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(navigator.currentInstruction)
                .font(.headline.weight(.bold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                metricPill("Segment", navigator.segmentRemainingMeters > 0 ? meters(navigator.segmentRemainingMeters) : "--")
                metricPill("Route", navigator.totalRemainingMeters > 0 ? meters(navigator.totalRemainingMeters) : "--")
                metricPill("Confidence", "\(Int(navigator.confidence * 100))%")
            }

            if let recoveryReason = navigator.recoveryReason {
                Label(recoveryReason, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stepHeader(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundColor(.black)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.92))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                Text(detail)
                    .routeCaption()
            }
        }
    }

    private func turnButton(_ hint: SemanticTurnHint, systemImage: String) -> some View {
        Button {
            captureTurn(hint)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.bold))
                Text(hint.displayName)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
        }
        .buttonStyle(SemanticRouteButtonStyle(prominence: .secondary))
        .disabled(!canUseARPose)
        .accessibilityLabel("Mark \(hint.displayName.lowercased()) turn")
    }

    private func metricPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(.white.opacity(0.55))
            Text(value)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundColor(.white.opacity(0.88))
        .padding(.vertical, 6)
        .padding(.horizontal, 9)
        .background(Color.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var selectedMapBinding: Binding<String> {
        Binding(
            get: { selectedARMapID ?? savedARMaps.first?.id ?? "" },
            set: { selectARMap($0.isEmpty ? nil : $0) }
        )
    }

    private var selectedRouteBinding: Binding<String> {
        Binding(
            get: { navigator.activeMap?.id ?? navigator.maps.first?.id ?? "" },
            set: { id in
                guard !id.isEmpty else { return }
                navigator.useMap(id: id)
                syncTargetName()
            }
        )
    }

    private func mapLabel(for map: ARStoredMapSummary) -> String {
        let suffix = map.poiCount == 1 ? "1 POI" : "\(map.poiCount) POIs"
        return "\(map.name) (\(suffix))"
    }

    private func routeLabel(for map: SemanticRouteMap) -> String {
        let targetCount = map.targetNames.count
        let suffix = targetCount == 1 ? "1 target" : "\(targetCount) targets"
        return "\(map.name) (\(suffix))"
    }

    private var borderColor: Color {
        navigator.phase == .recovering
            ? Color(red: 1.0, green: 0.78, blue: 0.48).opacity(0.62)
            : Color.white.opacity(0.14)
    }

    private var phaseColor: Color {
        switch navigator.phase {
        case .navigating:
            return Color.routeTeal
        case .recovering:
            return Color(red: 1.0, green: 0.78, blue: 0.48)
        case .arrived:
            return Color(red: 0.65, green: 0.82, blue: 1.0)
        case .mapping:
            return Color(red: 0.95, green: 0.72, blue: 0.42)
        case .ready:
            return Color.white.opacity(0.82)
        case .idle:
            return Color.white.opacity(0.46)
        }
    }

    private func syncStartName(force: Bool = false) {
        guard force || startName.trimmedRouteText.isEmpty else { return }
        startName = closestPOI ?? ""
    }

    private func syncTargetName() {
        if targetName.isEmpty, let first = navigator.availableTargets.first {
            targetName = first
        } else if !navigator.availableTargets.isEmpty, !navigator.availableTargets.contains(targetName) {
            targetName = navigator.availableTargets.first ?? ""
        }
    }

    private func meters(_ value: Double) -> String {
        value < 10 ? String(format: "%.1fm", value) : String(format: "%.0fm", value)
    }
}

private enum RoutePanelMode {
    case map
    case guide
}

private struct SemanticRouteButtonStyle: ButtonStyle {
    enum Prominence {
        case primary
        case secondary
    }

    var prominence: Prominence

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundColor(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(backgroundColor(configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        switch prominence {
        case .primary:
            return Color.routeTeal.opacity(isPressed ? 0.78 : 1)
        case .secondary:
            return Color.white.opacity(isPressed ? 0.18 : 0.11)
        }
    }
}

private struct SemanticIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundColor(.white.opacity(0.92))
            .background(Color.white.opacity(configuration.isPressed ? 0.18 : 0.11))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private extension Color {
    static let routeTeal = Color(red: 0.13, green: 0.54, blue: 0.49)
}

private extension String {
    var trimmedRouteText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Text {
    func routeCaption() -> some View {
        self
            .font(.caption.weight(.medium))
            .foregroundColor(.white.opacity(0.66))
            .fixedSize(horizontal: false, vertical: true)
    }

    func routeEyebrow() -> some View {
        self
            .font(.caption2.weight(.bold))
            .foregroundColor(.white.opacity(0.58))
            .textCase(.uppercase)
    }
}

private extension View {
    func routeTextField() -> some View {
        self
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .foregroundColor(.white)
            .background(Color.white.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    func routePickerFrame() -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    func routeSection() -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
