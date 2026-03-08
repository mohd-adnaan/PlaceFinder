//
//  Landingpageview.swift
//  IndoorNavigationTACME
//
//  Created by Mohammad Adnaan on 2026-03-07.
//
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
    var angle: CGFloat        // current angle on the orbit
    var radius: CGFloat       // orbit radius
    var phaseOffset: CGFloat  // random phase for organic motion
}

// MARK: - Landing Page View

struct LandingPageView: View {
    @EnvironmentObject var conversationManager: ConversationManager
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var ttsManager: TTSManager
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var sensorManager: IMUSensorManager

    // Settings & voice navigation bindings
    @Binding var showSettings: Bool
    @Binding var voiceControlledMode: Bool

    // Particle animation state
    @State private var particles: [Particle] = []
    @State private var animationTimer: Timer?
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.3

    // Interaction state
    @State private var isActive: Bool = false   // conversation or voice nav active
    @State private var showFeedbackText: Bool = false
    @State private var feedbackText: String = ""

    // Voice navigation manager reference
    @EnvironmentObject var voiceNavManager: VoiceNavigationManager

    private let particleCount = 180
    private let orbRadius: CGFloat = 140

    var body: some View {
        ZStack {
            // Full black background
            Color.black
                .ignoresSafeArea()

            // Particle orb
            particleOrbView
                .frame(width: orbRadius * 2.5, height: orbRadius * 2.5)
                .scaleEffect(pulseScale)

            // Top bar with settings icon
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

            // Bottom text and status
            VStack {
                Spacer()

                // Feedback text (appears briefly on double tap)
                if showFeedbackText {
                    Text(feedbackText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.8))
                        .transition(.opacity)
                        .padding(.bottom, 4)
                }

                // Status text
                statusText
                    .padding(.bottom, 60)

                // Voice navigation status (when active)
                if voiceNavManager.voiceInputState.currentMode != .none {
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
            if active {
                withAnimation(.easeInOut(duration: 0.5)) {
                    pulseScale = 1.08
                    glowOpacity = 0.5
                }
            } else {
                withAnimation(.easeInOut(duration: 0.5)) {
                    pulseScale = 1.0
                    glowOpacity = 0.3
                }
            }
        }
        .onChange(of: voiceNavManager.voiceInputState.isComplete) { complete in
            if complete {
                // Voice navigation completed — auto-initialize
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
            } else if voiceNavManager.voiceInputState.currentMode != .none {
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

    // MARK: - Voice Nav Status

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

                // Gold/amber color with varying warmth
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

            // Central glow
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

    // MARK: - Particle Generation

    private func generateParticles() {
        particles = (0..<particleCount).map { _ in
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let radius = CGFloat.random(in: 20...orbRadius)
            let x = cos(angle) * radius
            let y = sin(angle) * radius

            return Particle(
                x: x,
                y: y,
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
            // Orbital motion
            particles[i].angle += particles[i].speed * speedMultiplier

            // Organic radius variation using sine wave
            let radiusVariation = sin(time * 0.5 + particles[i].phaseOffset) * 15
            let currentRadius = particles[i].radius + radiusVariation

            particles[i].x = cos(particles[i].angle) * currentRadius
            particles[i].y = sin(particles[i].angle) * currentRadius

            // Pulse opacity when active
            if isActive {
                let opacityPulse = sin(time * 2.0 + particles[i].phaseOffset) * 0.2
                particles[i].opacity = min(1.0, max(0.15, particles[i].opacity + Double(opacityPulse) * 0.01))
            }
        }
    }

    // MARK: - Interaction

    private func handleDoubleTap() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        if voiceControlledMode {
            // Voice controlled mode: toggle voice navigation
            handleVoiceControlledDoubleTap()
        } else {
            // Normal mode: toggle conversation
            handleConversationDoubleTap()
        }
    }

    private func handleConversationDoubleTap() {
        if conversationManager.conversationState.isActive {
            // Deactivate conversation mode
            conversationManager.stopConversationMode()
            showBriefFeedback(languageManager.currentLanguage == .french
                              ? "Mode conversation désactivé"
                              : "Conversation mode off")
        } else {
            // Activate conversation mode
            conversationManager.startConversationMode()
            showBriefFeedback(languageManager.currentLanguage == .french
                              ? "Mode conversation activé"
                              : "Conversation mode on")
        }
    }

    private func handleVoiceControlledDoubleTap() {
        if voiceNavManager.voiceInputState.currentMode != .none {
            // Already in voice nav flow — cancel it
            voiceNavManager.cancelVoiceInput()
            showBriefFeedback("Voice navigation cancelled")
        } else if conversationManager.conversationState.isActive {
            // If conversation is active, toggle listening
            if conversationManager.conversationState.isListening {
                conversationManager.stopListening()
            } else {
                conversationManager.startListening()
            }
        } else {
            // Start voice navigation flow
            voiceNavManager.startVoiceInput(poiNames: navigationManager.poiNames)
            showBriefFeedback("Voice navigation started")
        }
    }

    private func handleVoiceNavigationComplete() {
        let source = voiceNavManager.voiceInputState.source
        let destination = voiceNavManager.voiceInputState.destination

        guard !source.isEmpty, !destination.isEmpty else { return }

        showBriefFeedback("Navigating: \(source) → \(destination)")

        // Auto-initialize navigation with the voice-selected locations
        Task {
            let result = await navigationManager.initializeWithServer(
                source: source,
                destination: destination,
                useClockDirections: UserDefaults.standard.bool(forKey: "useClockDirections"),
                useLandmarks: UserDefaults.standard.bool(forKey: "useLandmarks"),
                conversationMode: false
            )

            if case .success = result {
                // Auto-start navigation after initialization
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
