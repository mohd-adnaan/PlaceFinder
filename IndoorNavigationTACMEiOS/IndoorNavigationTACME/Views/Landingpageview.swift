//
//  LandingPageView.swift
//  IndoorNavigationTACME
//
//  Minimalist landing page with animated particle orb.
//  Double-tap toggles conversation mode or voice navigation mode.
//

import SwiftUI

// MARK: - Particle Model

struct Particle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var opacity: Double
    var speed: CGFloat
    var angle: CGFloat
    var radius: CGFloat
    var phaseOffset: CGFloat
}

// MARK: - Landing Page View

struct LandingPageView: View {
    @EnvironmentObject var conversationManager: ConversationManager
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var ttsManager: TTSManager
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var sensorManager: IMUSensorManager
    @EnvironmentObject var voiceNavManager: VoiceNavigationManager

    @Binding var showSettings: Bool
    @Binding var voiceControlledMode: Bool

    @State private var particles: [Particle] = []
    @State private var animationTimer: Timer?
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.3
    @State private var isActive: Bool = false
    @State private var showFeedbackText: Bool = false
    @State private var feedbackText: String = ""

    private let particleCount = 180
    private let orbRadius: CGFloat = 140

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            particleOrbView
                .frame(width: orbRadius * 2.5, height: orbRadius * 2.5)
                .scaleEffect(pulseScale)

            // Settings gear icon (top-right)
            VStack {
                HStack {
                    Spacer()
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(12)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens navigation settings")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                Spacer()
            }

            // Bottom status area
            VStack {
                Spacer()

                if showFeedbackText {
                    Text(feedbackText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.8))
                        .transition(.opacity)
                        .padding(.bottom, 4)
                }

                statusText
                    .padding(.bottom, 60)

                // Voice nav status card (only when voice flow is active)
                if voiceNavManager.voiceInputState.currentMode != .idle {
                    voiceNavStatusView
                        .padding(.bottom, 20)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            handleDoubleTap()
        }
        .onAppear {
            generateParticles()
            startAnimation()
            sensorManager.startSensors()
        }
        .onDisappear {
            stopAnimation()
        }
        .onChange(of: conversationManager.conversationState.isActive) { active in
            isActive = active
            withAnimation(.easeInOut(duration: 0.5)) {
                pulseScale = active ? 1.08 : 1.0
                glowOpacity = active ? 0.5 : 0.3
            }
        }
        .onChange(of: voiceNavManager.voiceInputState.isComplete) { complete in
            if complete {
                handleVoiceNavigationComplete()
            }
        }
    }

    // MARK: - Status Text

    private var statusText: some View {
        Group {
            if conversationManager.conversationState.isActive {
                if conversationManager.conversationState.isListening {
                    Text(languageManager.currentLanguage == .french
                         ? "Écoute en cours..."
                         : "Listening...")
                        .font(.title3)
                        .fontWeight(.light)
                        .foregroundColor(.white.opacity(0.7))
                } else {
                    Text(languageManager.currentLanguage == .french
                         ? "Appuyez deux fois pour parler"
                         : "Double-tap to speak")
                        .font(.title3)
                        .fontWeight(.light)
                        .foregroundColor(.white.opacity(0.5))
                }
            } else if voiceNavManager.voiceInputState.currentMode != .idle {
                Text(voiceNavManager.voiceInputState.debugInfo)
                    .font(.subheadline)
                    .fontWeight(.light)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                Text(languageManager.currentLanguage == .french
                     ? "Dites quelque chose..."
                     : "Say something...")
                    .font(.title3)
                    .fontWeight(.light)
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    // MARK: - Voice Nav Status Card

    private var voiceNavStatusView: some View {
        VStack(spacing: 8) {
            if !voiceNavManager.voiceInputState.confirmationPrompt.isEmpty {
                Text(voiceNavManager.voiceInputState.confirmationPrompt)
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if voiceNavManager.voiceInputState.isListening {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("Listening")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.8))
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .padding(.horizontal, 20)
    }

    // MARK: - Particle Orb

    private var particleOrbView: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            for particle in particles {
                let point = CGPoint(
                    x: center.x + particle.x,
                    y: center.y + particle.y
                )

                let warmth = particle.opacity
                let color = Color(
                    red: 0.85 + warmth * 0.15,
                    green: 0.65 + warmth * 0.2,
                    blue: 0.2 + warmth * 0.1,
                    opacity: particle.opacity * (isActive ? 0.9 : 0.6)
                )

                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - particle.size / 2,
                        y: point.y - particle.size / 2,
                        width: particle.size,
                        height: particle.size
                    )),
                    with: .color(color)
                )
            }

            let glowSize: CGFloat = isActive ? 60 : 40
            let glowGradient = Gradient(colors: [
                Color(red: 0.9, green: 0.7, blue: 0.3, opacity: glowOpacity),
                Color(red: 0.9, green: 0.7, blue: 0.3, opacity: 0)
            ])
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - glowSize,
                    y: center.y - glowSize,
                    width: glowSize * 2,
                    height: glowSize * 2
                )),
                with: .radialGradient(
                    glowGradient,
                    center: center,
                    startRadius: 0,
                    endRadius: glowSize
                )
            )
        }
    }

    // MARK: - Particle Animation

    private func generateParticles() {
        particles = (0..<particleCount).map { _ in
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let radius = CGFloat.random(in: 20...orbRadius)
            return Particle(
                x: cos(angle) * radius,
                y: sin(angle) * radius,
                size: CGFloat.random(in: 1.5...4.5),
                opacity: Double.random(in: 0.2...0.8),
                speed: CGFloat.random(in: 0.002...0.012),
                angle: angle,
                radius: radius,
                phaseOffset: CGFloat.random(in: 0...(2 * .pi))
            )
        }
    }

    private func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            updateParticles()
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func updateParticles() {
        let speedMultiplier: CGFloat = isActive ? 1.8 : 1.0
        let time = CGFloat(Date().timeIntervalSince1970)

        for i in particles.indices {
            particles[i].angle += particles[i].speed * speedMultiplier
            let radiusVariation = sin(time * 0.5 + particles[i].phaseOffset) * 15
            let currentRadius = particles[i].radius + radiusVariation
            particles[i].x = cos(particles[i].angle) * currentRadius
            particles[i].y = sin(particles[i].angle) * currentRadius

            if isActive {
                let opacityPulse = sin(time * 2.0 + particles[i].phaseOffset) * 0.2
                particles[i].opacity = min(1.0, max(0.15, particles[i].opacity + Double(opacityPulse) * 0.01))
            }
        }
    }

    // MARK: - Interaction Handlers

    private func handleDoubleTap() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        if voiceControlledMode {
            handleVoiceControlledDoubleTap()
        } else {
            handleConversationDoubleTap()
        }
    }

    private func handleConversationDoubleTap() {
        if conversationManager.conversationState.isActive {
            conversationManager.stopConversationMode()
            showBriefFeedback(languageManager.currentLanguage == .french
                              ? "Mode conversation désactivé"
                              : "Conversation mode off")
        } else {
            conversationManager.startConversationMode()
            showBriefFeedback(languageManager.currentLanguage == .french
                              ? "Mode conversation activé"
                              : "Conversation mode on")
        }
    }

    private func handleVoiceControlledDoubleTap() {
        // Check voice nav mode using .idle (NOT .none — avoids Optional.none ambiguity)
        let voiceMode: VoiceNavigationManager.InputMode = voiceNavManager.voiceInputState.currentMode

        if voiceMode != .idle {
            voiceNavManager.cancelVoiceInput()
            showBriefFeedback("Voice navigation cancelled")
            return
        }

        let convActive: Bool = conversationManager.conversationState.isActive
        if convActive {
            let listening: Bool = conversationManager.conversationState.isListening
            if listening {
                conversationManager.stopListening()
            } else {
                conversationManager.startListening()
            }
            return
        }

        // Start voice navigation flow
        let pois: [String] = navigationManager.poiNames
        voiceNavManager.startVoiceInput(poiNames: pois)
        showBriefFeedback("Voice navigation started")
    }

    private func handleVoiceNavigationComplete() {
        let src: String = voiceNavManager.voiceInputState.source
        let dst: String = voiceNavManager.voiceInputState.destination
        guard !src.isEmpty, !dst.isEmpty else { return }

        showBriefFeedback("Navigating: \(src) → \(dst)")

        Task {
            let result = await navigationManager.initializeWithServer(
                source: src,
                destination: dst,
                useClockDirections: UserDefaults.standard.bool(forKey: "useClockDirections"),
                useLandmarks: UserDefaults.standard.bool(forKey: "useLandmarks"),
                conversationMode: false
            )
            if case .success = result {
                let _ = await navigationManager.startNavigationWithCalibration()
            }
        }
    }

    private func showBriefFeedback(_ text: String) {
        feedbackText = text
        withAnimation(.easeIn(duration: 0.2)) {
            showFeedbackText = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                showFeedbackText = false
            }
        }
    }
}
