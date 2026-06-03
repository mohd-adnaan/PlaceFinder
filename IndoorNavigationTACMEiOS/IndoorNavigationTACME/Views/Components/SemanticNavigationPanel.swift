import SwiftUI

struct SemanticNavigationPanel: View {
    @ObservedObject var navigator: SemanticRouteNavigator
    let canCaptureRoutePoint: Bool
    let beginWalkthrough: (String) -> Void
    let captureRoutePoint: (String) -> Void
    let captureTurn: (SemanticTurnHint) -> Void
    let captureLandmark: (String, SemanticRouteSide, String, Bool) -> Void
    let saveWalkthrough: () -> Void
    let startNavigation: (String) -> Void
    let snapToRoute: () -> Void

    @State private var mapName: String = ""
    @State private var routePointName: String = ""
    @State private var semanticLabel: String = ""
    @State private var targetName: String = ""
    @State private var landmarkContext: String = ""
    @State private var selectedSide: SemanticRouteSide = .left
    @State private var showsBuilder = false
    @State private var showsRAGContext = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            guidanceStatus

            if showsBuilder {
                builderControls
            }

            navigationControls

            if showsRAGContext {
                ragContextPreview
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.58))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear(perform: syncTargetIfNeeded)
        .onChange(of: navigator.availableTargets) { _, _ in
            syncTargetIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Semantic Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))

            Spacer()

            confidencePill

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsBuilder.toggle()
                }
            } label: {
                Image(systemName: showsBuilder ? "wrench.and.screwdriver.fill" : "wrench.and.screwdriver")
                    .font(.caption.weight(.bold))
                    .frame(width: 32, height: 28)
            }
            .buttonStyle(SemanticIconButtonStyle())
            .accessibilityLabel(showsBuilder ? "Hide route builder" : "Show route builder")

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsRAGContext.toggle()
                }
            } label: {
                Image(systemName: "text.badge.checkmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 32, height: 28)
            }
            .buttonStyle(SemanticIconButtonStyle())
            .accessibilityLabel(showsRAGContext ? "Hide RAG context" : "Show RAG context")
        }
    }

    private var confidencePill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(phaseColor)
                .frame(width: 7, height: 7)
            Text(navigator.phase.displayName)
                .font(.caption2.weight(.semibold))
            Text(String(format: "%.0f%%", navigator.confidence * 100))
                .font(.system(.caption2, design: .monospaced).weight(.bold))
        }
        .foregroundColor(.white.opacity(0.82))
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var guidanceStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(navigator.currentInstruction)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.94))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                metricPill(
                    title: "Segment",
                    value: navigator.phase == .navigating || navigator.phase == .recovering
                        ? meters(navigator.segmentRemainingMeters)
                        : "--"
                )
                metricPill(
                    title: "Route",
                    value: navigator.totalRemainingMeters > 0 ? meters(navigator.totalRemainingMeters) : "--"
                )
                metricPill(
                    title: "Step",
                    value: navigator.routeSteps.isEmpty
                        ? "--"
                        : "\(navigator.currentStepIndex + 1)/\(navigator.routeSteps.count)"
                )
            }

            if let recoveryReason = navigator.recoveryReason {
                Label(recoveryReason, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundColor(Color(red: 1.0, green: 0.74, blue: 0.46))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var builderControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Semantic map name", text: $mapName)
                    .routeTextField()

                Button {
                    beginWalkthrough(mapName)
                } label: {
                    Image(systemName: "plus.viewfinder")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(SemanticIconButtonStyle(prominence: .primary))
                .accessibilityLabel("Start walk map")
            }

            HStack(spacing: 8) {
                metricPill(title: "Captured", value: "\(navigator.capturedPointCount) pts")
                metricPill(title: "Measured", value: meters(navigator.capturedDistanceMeters))
                metricPill(title: "Quality", value: navigator.mappingQualityText)
            }

            HStack(spacing: 8) {
                TextField("Checkpoint name", text: $routePointName)
                    .routeTextField()

                Button {
                    captureRoutePoint(routePointName)
                    routePointName = ""
                } label: {
                    Label("Point", systemImage: "mappin.and.ellipse")
                        .frame(width: 82)
                }
                .buttonStyle(SemanticRouteButtonStyle(prominence: .secondary))
                .disabled(!canCaptureRoutePoint)
            }

            HStack(spacing: 8) {
                turnButton(.left, systemImage: "arrow.turn.up.left")
                turnButton(.right, systemImage: "arrow.turn.up.right")
                turnButton(.straight, systemImage: "arrow.up")
                turnButton(.corner, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            }

            TextField("Object or target name", text: $semanticLabel)
                .routeTextField()

            HStack(spacing: 8) {
                Picker("Side", selection: $selectedSide) {
                    ForEach(SemanticRouteSide.allCases) { side in
                        Text(side.displayName).tag(side)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .frame(width: 84)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    captureLandmark(semanticLabel, selectedSide, landmarkContext, true)
                    syncMarkedLabel()
                } label: {
                    Label("Target", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SemanticRouteButtonStyle(prominence: .primary))
                .disabled(!canCaptureRoutePoint || semanticLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    captureLandmark(semanticLabel, selectedSide, landmarkContext, false)
                    syncMarkedLabel()
                } label: {
                    Label("Object", systemImage: "tag")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SemanticRouteButtonStyle(prominence: .secondary))
                .disabled(!canCaptureRoutePoint || semanticLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextField("Shelf note", text: $landmarkContext)
                .routeTextField()

            HStack(spacing: 8) {
                Button {
                    saveWalkthrough()
                    syncTargetIfNeeded()
                } label: {
                    Label("Save Semantic Map", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SemanticRouteButtonStyle(prominence: .primary))

                Button {
                    navigator.discardCapture()
                    syncTargetIfNeeded()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(SemanticIconButtonStyle())
                .accessibilityLabel("Discard semantic capture")
            }
        }
    }

    private var navigationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !navigator.availableTargets.isEmpty {
                Picker("Target", selection: $targetName) {
                    ForEach(navigator.availableTargets, id: \.self) { target in
                        Text(target).tag(target)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                TextField("Target, e.g. onions", text: $targetName)
                    .routeTextField()
            }

            HStack(spacing: 8) {
                Button {
                    startNavigation(targetName)
                } label: {
                    Label("Guide", systemImage: "figure.walk.motion")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SemanticRouteButtonStyle(prominence: .primary))
                .disabled(targetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    snapToRoute()
                } label: {
                    Image(systemName: "scope")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(SemanticIconButtonStyle())
                .accessibilityLabel("Snap to nearest route edge")

                Button {
                    navigator.stopNavigation()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(SemanticIconButtonStyle())
                .accessibilityLabel("Stop semantic navigation")
            }
        }
    }

    private var ragContextPreview: some View {
        ScrollView {
            Text(navigator.ragContextJSON)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.white.opacity(0.76))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(8)
        }
        .frame(maxHeight: 132)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func turnButton(_ hint: SemanticTurnHint, systemImage: String) -> some View {
        Button {
            captureTurn(hint)
        } label: {
            Label(hint.displayName, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
        }
        .buttonStyle(SemanticRouteButtonStyle(prominence: .secondary))
        .disabled(!canCaptureRoutePoint)
        .accessibilityLabel("Mark \(hint.displayName.lowercased()) turn")
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(.white.opacity(0.54))
            Text(value)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundColor(.white.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var borderColor: Color {
        navigator.phase == .recovering
            ? Color(red: 1.0, green: 0.74, blue: 0.46).opacity(0.55)
            : Color.white.opacity(0.12)
    }

    private var phaseColor: Color {
        switch navigator.phase {
        case .navigating:
            return Color(red: 0.56, green: 0.84, blue: 0.78)
        case .recovering:
            return Color(red: 1.0, green: 0.74, blue: 0.46)
        case .arrived:
            return Color(red: 0.66, green: 0.82, blue: 1.0)
        case .mapping:
            return Color(red: 0.92, green: 0.72, blue: 0.42)
        case .ready:
            return Color.white.opacity(0.78)
        case .idle:
            return Color.white.opacity(0.45)
        }
    }

    private func meters(_ value: Double) -> String {
        value < 10 ? String(format: "%.1fm", value) : String(format: "%.0fm", value)
    }

    private func syncTargetIfNeeded() {
        if targetName.isEmpty, let first = navigator.availableTargets.first {
            targetName = first
        } else if !navigator.availableTargets.isEmpty && !navigator.availableTargets.contains(targetName) {
            targetName = navigator.availableTargets.first ?? ""
        }
    }

    private func syncMarkedLabel() {
        if !semanticLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            targetName = semanticLabel
        }
    }
}

private struct SemanticRouteButtonStyle: ButtonStyle {
    enum Prominence {
        case primary
        case secondary
    }

    var prominence: Prominence

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .background(backgroundColor(configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        switch prominence {
        case .primary:
            return Color(red: 0.12, green: 0.50, blue: 0.46).opacity(isPressed ? 0.80 : 1)
        case .secondary:
            return Color.white.opacity(isPressed ? 0.16 : 0.11)
        }
    }
}

private struct SemanticIconButtonStyle: ButtonStyle {
    enum Prominence {
        case primary
        case secondary
    }

    var prominence: Prominence = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .foregroundColor(.white.opacity(0.92))
            .background(backgroundColor(configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        switch prominence {
        case .primary:
            return Color(red: 0.12, green: 0.50, blue: 0.46).opacity(isPressed ? 0.80 : 1)
        case .secondary:
            return Color.white.opacity(isPressed ? 0.16 : 0.11)
        }
    }
}

private extension View {
    func routeTextField() -> some View {
        self
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .font(.caption.weight(.medium))
            .padding(.vertical, 10)
            .padding(.horizontal, 11)
            .foregroundColor(.white)
            .background(Color.white.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
