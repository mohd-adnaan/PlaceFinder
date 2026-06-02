import SwiftUI
import ARKit

struct ARViewContainer: UIViewRepresentable {
    var session: ARSession
    var isSessionActive: Bool
    var showsCoaching: Bool

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.session = session
        arView.debugOptions = []
        arView.preferredFramesPerSecond = 30
        arView.antialiasingMode = .none
        arView.rendersContinuously = false
        arView.autoenablesDefaultLighting = false
        arView.automaticallyUpdatesLighting = false
        arView.backgroundColor = .black
        context.coordinator.attachCoachingOverlay(to: arView, session: session)
        context.coordinator.update(showsCoaching: showsCoaching && isSessionActive)
        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        uiView.debugOptions = []
        context.coordinator.update(showsCoaching: showsCoaching && isSessionActive)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        private let coachingOverlay = ARCoachingOverlayView()

        func attachCoachingOverlay(to arView: ARSCNView, session: ARSession) {
            coachingOverlay.session = session
            coachingOverlay.goal = .tracking
            coachingOverlay.activatesAutomatically = false
            coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
            coachingOverlay.isHidden = true

            arView.addSubview(coachingOverlay)
            NSLayoutConstraint.activate([
                coachingOverlay.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
                coachingOverlay.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
                coachingOverlay.topAnchor.constraint(equalTo: arView.topAnchor),
                coachingOverlay.bottomAnchor.constraint(equalTo: arView.bottomAnchor)
            ])
        }

        func update(showsCoaching: Bool) {
            coachingOverlay.isHidden = !showsCoaching
            coachingOverlay.activatesAutomatically = showsCoaching
            if !showsCoaching {
                coachingOverlay.setActive(false, animated: true)
            }
        }
    }
}

struct ARMappingView: View {
    @StateObject private var mappingManager = ARMappingManager()
    @State private var newPOIName: String = ""

    var body: some View {
        ZStack {
            ARViewContainer(
                session: mappingManager.session,
                isSessionActive: mappingManager.sessionMode != .idle,
                showsCoaching: mappingManager.isMapping || (mappingManager.isRelocalizing && !mappingManager.isLocalized)
            )
            .ignoresSafeArea()

            if mappingManager.sessionMode == .idle {
                Color.black.opacity(0.82)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                headerHUD
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                Spacer(minLength: 24)

                controlsPanel
                    .padding(.horizontal, 20)
                    .padding(.bottom, 22)
            }
        }
        .navigationTitle("AR Localization")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onDisappear {
            mappingManager.stopMapping()
        }
    }

    private var headerHUD: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 8, height: 8)

                Text(statusText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer()

                if let closestPOI = mappingManager.closestPOI {
                    Label(closestPOI, systemImage: "location.viewfinder")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else if let poiMatchStatusText = mappingManager.poiMatchStatusText {
                    Text(poiMatchStatusText)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.68))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            if !mappingManager.currentPositionText.isEmpty {
                Text(mappingManager.currentPositionText)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundColor(.white.opacity(0.82))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = mappingManager.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.52))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !mappingManager.anchorsList.isEmpty {
                poiStrip
            }

            if mappingManager.sessionMode == .idle {
                idleControls
            } else {
                if canPinPOI {
                    poiInput
                }
                activeControls
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.62))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var idleControls: some View {
        VStack(spacing: 10) {
            Button(action: { mappingManager.startMapping() }) {
                Label("Start Mapping", systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ARControlButtonStyle(prominence: .primary))

            Button(action: { mappingManager.loadMapAndRelocalize() }) {
                Label("Load Saved Map", systemImage: "location.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ARControlButtonStyle(prominence: .secondary))
        }
    }

    private var poiInput: some View {
        HStack(spacing: 10) {
            TextField("POI name", text: $newPOIName)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .padding(.vertical, 11)
                .padding(.horizontal, 12)
                .foregroundColor(.white)
                .background(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: pinPOI) {
                Label("Pin", systemImage: "mappin.and.ellipse")
            }
            .buttonStyle(ARControlButtonStyle(prominence: .compact))
        }
    }

    private var activeControls: some View {
        HStack(spacing: 10) {
            Button(action: { mappingManager.saveMap() }) {
                Label(mappingManager.isSavingMap ? "Saving" : saveButtonTitle, systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ARControlButtonStyle(prominence: .primary))
            .disabled(mappingManager.isSavingMap)

            Button(action: { mappingManager.stopMapping() }) {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ARControlButtonStyle(prominence: .secondary))
        }
    }

    private var poiStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(mappingManager.anchorsList, id: \.self) { poi in
                    Text(poi)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .foregroundColor(.white.opacity(0.88))
                        .background(Color.white.opacity(0.10))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func pinPOI() {
        mappingManager.addPOIAnchor(name: newPOIName)
        if mappingManager.statusMessage?.hasPrefix("Pinned") == true {
            newPOIName = ""
        }
    }

    private var saveButtonTitle: String {
        mappingManager.isRelocalizing ? "Save Expanded Map" : "Save Map"
    }

    private var canPinPOI: Bool {
        mappingManager.isMapping || mappingManager.isLocalized
    }

    private var statusTint: Color {
        if mappingManager.isLocalized {
            return Color(red: 0.56, green: 0.84, blue: 0.78)
        }
        if mappingManager.isMapping || mappingManager.isRelocalizing {
            return Color(red: 0.86, green: 0.68, blue: 0.38)
        }
        return Color.white.opacity(0.64)
    }

    private var statusText: String {
        if mappingManager.isRelocalizing {
            return mappingManager.isLocalized ? "Localized" : "Searching saved map"
        }

        if !mappingManager.isMapping {
            return "Ready"
        }

        switch mappingManager.mappingStatus {
        case .notAvailable:
            return "Starting map"
        case .limited:
            return "Scanning limited"
        case .extending:
            return "Extending map"
        case .mapped:
            return "Map quality good"
        @unknown default:
            return "Tracking"
        }
    }
}

private enum ARControlProminence {
    case primary
    case secondary
    case compact
}

private struct ARControlButtonStyle: ButtonStyle {
    var prominence: ARControlProminence

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundColor(foregroundColor)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, 12)
            .background(background(configuration: configuration))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }

    private var font: Font {
        switch prominence {
        case .compact:
            return .subheadline.weight(.semibold)
        default:
            return .callout.weight(.semibold)
        }
    }

    private var verticalPadding: CGFloat {
        prominence == .compact ? 11 : 13
    }

    private var foregroundColor: Color {
        prominence == .primary ? .black : .white
    }

    private func background(configuration: Configuration) -> some View {
        let fill: Color
        switch prominence {
        case .primary:
            fill = Color.white.opacity(configuration.isPressed ? 0.82 : 0.94)
        case .secondary:
            fill = Color.white.opacity(configuration.isPressed ? 0.16 : 0.10)
        case .compact:
            fill = Color.white.opacity(configuration.isPressed ? 0.22 : 0.14)
        }

        return RoundedRectangle(cornerRadius: 8)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(prominence == .primary ? 0 : 0.16), lineWidth: 1)
            )
    }
}
