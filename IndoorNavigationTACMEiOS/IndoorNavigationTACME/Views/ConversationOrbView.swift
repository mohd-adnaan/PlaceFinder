//
//  ConversationOrbView.swift
//  IndoorNavigationTACME
//
//  Created by Mohammad Adnaan on 2026-02-23.
//

import SwiftUI

// MARK: - Particle data (generated once, never mutated)

private struct OrbParticle {
    let theta:     Double   // azimuthal  0 … 2π
    let phi:       Double   // elevation -π/2 … π/2
    let speed:     Double   // oscillation speed
    let phase:     Double   // random phase offset
    let size:      CGFloat  // dot radius
    let hue:       Double   // base hue (warm orange-brown range)

    static func generate(count: Int) -> [OrbParticle] {
        (0..<count).map { _ in
            OrbParticle(
                theta: .random(in: 0 ..< 2 * .pi),
                phi:   .random(in: -.pi/2 ... .pi/2),
                speed: .random(in: 0.4 ... 1.8),
                phase: .random(in: 0 ..< 2 * .pi),
                size:  .random(in: 1.4 ... 3.2),
                hue:   .random(in: 0.06 ... 0.12)  // orange-amber
            )
        }
    }
}

// MARK: - Main View

struct ConversationOrbView: View {
    @ObservedObject var conversationManager: ConversationManager
    /// Called when user wants to exit (X button).
    let onDismiss: () -> Void

    // Stable particle set — never regenerated.
    private let particles = OrbParticle.generate(count: 320)

    var body: some View {
        ZStack {
            // ── Background ──────────────────────────────────────────────
            Color.black.ignoresSafeArea()

            // ── Particle Orb ────────────────────────────────────────────
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { tl in
                Canvas { ctx, size in
                    drawOrb(ctx: ctx, size: size, time: tl.date.timeIntervalSinceReferenceDate)
                }
                .ignoresSafeArea()
            }

            // ── Bottom HUD ──────────────────────────────────────────────
            VStack {
                Spacer()

                // Status label
                Text(statusLabel)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
                    .padding(.bottom, 28)

                // Controls row
                HStack {
                    // X  –  exit conversation mode
                    Button(action: onDismiss) {
                        Circle()
                            .fill(.white.opacity(0.12))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: "xmark")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                    }
                    .accessibilityLabel("Exit conversation mode")

                    Spacer()

                    // Mic indicator (non-interactive, just visual feedback)
                    Circle()
                        .fill(micFill)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: micIcon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                        )
                        .animation(.easeInOut(duration: 0.3), value: conversationManager.conversationState.isListening)
                }
                .padding(.horizontal, 44)
                .padding(.bottom, 52)
            }
        }
    }

    // MARK: – Helpers

    private var statusLabel: String {
        let state = conversationManager.conversationState
        if state.isProcessing { return "Thinking…" }
        if state.isListening  { return "Listening…" }
        return "Say something…"
    }

    private var micIcon: String {
        conversationManager.conversationState.isListening ? "mic.fill" : "mic"
    }

    private var micFill: Color {
        conversationManager.conversationState.isListening
            ? Color.red.opacity(0.35)
            : Color.white.opacity(0.10)
    }

    // MARK: – Canvas drawing

    private func drawOrb(ctx: GraphicsContext, size: CGSize, time: Double) {
        let center  = CGPoint(x: size.width / 2, y: size.height / 2)
        let base    = min(size.width, size.height) * 0.34
        let state   = conversationManager.conversationState
        let level   = CGFloat(conversationManager.audioLevel)   // 0…1
        let listening  = state.isListening
        let processing = state.isProcessing

        for p in particles {
            // ── Scale factor (drives orb "breathing") ──────────────────
            let scale: CGFloat
            if listening {
                // Pulse with audio level + gentle noise
                let noise = CGFloat(sin(time * p.speed + p.phase)) * 0.04
                scale = 1.0 + level * 0.5 + noise
            } else if processing {
                // Energetic spin
                scale = 1.0 + CGFloat(sin(time * 3.5 + p.phase)) * 0.12
            } else {
                // Idle breathe
                scale = 1.0 + CGFloat(sin(time * 1.2 + p.phase)) * 0.03
            }

            let r = base * scale

            // ── 3D → 2D projection ─────────────────────────────────────
            let sinT = CGFloat(sin(p.theta + time * 0.08))
            let cosT = CGFloat(cos(p.theta + time * 0.08))
            let sinP = CGFloat(sin(p.phi))
            let cosP = CGFloat(cos(p.phi))

            let x3 = r * cosP * cosT
            let y3 = r * cosP * sinT
            let z3 = r * sinP          // depth

            // Simple orthographic projection
            let px = center.x + x3
            let py = center.y - z3

            // Depth-based opacity & size
            let depth = (y3 / r + 1) / 2    // 0 (back) … 1 (front)
            let opacity: CGFloat = 0.25 + depth * 0.75
            let dotSize = p.size * (0.6 + depth * 0.7) * (listening ? 1.0 + level * 0.6 : 1.0)

            // ── Color ──────────────────────────────────────────────────
            let brightness: Double
            let saturation: Double
            if listening {
                brightness = 0.55 + Double(level) * 0.35 + Double(depth) * 0.15
                saturation = 0.80
            } else if processing {
                brightness = 0.60 + abs(sin(time * 2.0 + p.phase)) * 0.25
                saturation = 0.90
            } else {
                brightness = 0.38 + Double(depth) * 0.25
                saturation = 0.55
            }

            let color = Color(hue: p.hue, saturation: saturation, brightness: brightness)

            ctx.fill(
                Path(ellipseIn: CGRect(x: px - dotSize/2, y: py - dotSize/2,
                                       width: dotSize,   height: dotSize)),
                with: .color(color.opacity(opacity))
            )
        }
    }
}
