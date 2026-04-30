import SwiftUI
import AmachBreatheShared

/// Animated breathing coach for the Watch. Drives every visual purely from
/// the PacerState published by MasterPhaseTimer — no separate clock.
///
/// Layout (from outside in):
///   • Static track ring
///   • Soft emerald halo that brightens at the inhale peak
///   • Animated emerald ring that scales 0.6 → 1.4 with the breath
///   • Crossfading "Inhale" / "Exhale" label, with optional pause glyph
struct BreathingCoachView: View {

    let pacerState: PacerState
    let isPaused: Bool
    let isRecovery: Bool
    /// Coherence score 0…1 (tints the halo a touch when high). nil = ignore.
    let coherence: Double?

    private let ringDiameter: CGFloat = 110

    var body: some View {
        ZStack {
            haloLayer
            trackRing
            animatedRing
            centerLabel
        }
        .frame(width: ringDiameter, height: ringDiameter)
        // Smooth the per-tick ringScale changes (60 Hz updates → tiny linear tween).
        .animation(.linear(duration: 1.0 / 60.0), value: pacerState.ringScale)
        .animation(.easeInOut(duration: 0.35), value: pacerState.breathPhase)
    }

    // MARK: - Layers

    private var haloLayer: some View {
        // Halo brightens as the ring expands — peaks at inhale top.
        // ringScale ∈ [0.6, 1.4] → normalized ∈ [0, 1].
        let breath = (pacerState.ringScale - 0.6) / 0.8
        let intensity = max(0, min(1, breath))
        let coherenceBoost = (coherence ?? 0).clamped(0, 1) * 0.25
        return Circle()
            .fill(haloColor)
            .frame(width: ringDiameter, height: ringDiameter)
            .scaleEffect(0.95 + 0.25 * pacerState.ringScale)
            .opacity(0.18 + 0.32 * intensity + coherenceBoost)
            .blur(radius: 14)
    }

    private var trackRing: some View {
        Circle()
            .stroke(ringColor.opacity(0.18), lineWidth: 2)
            .frame(width: ringDiameter, height: ringDiameter)
    }

    private var animatedRing: some View {
        Circle()
            .stroke(
                ringColor,
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .frame(width: ringDiameter, height: ringDiameter)
            .scaleEffect(pacerState.ringScale)
            .shadow(color: ringColor.opacity(0.55), radius: ringGlowRadius)
    }

    private var centerLabel: some View {
        ZStack {
            phaseText("Inhale")
                .opacity(pacerState.breathPhase == .inhale ? 1 : 0)
            phaseText("Exhale")
                .opacity(pacerState.breathPhase == .exhale ? 1 : 0)

            if isPaused {
                VStack(spacing: 1) {
                    Spacer().frame(height: 18)
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.amachTextSecondary)
                }
            }
        }
    }

    private func phaseText(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.amachTextPrimary)
            .tracking(0.5)
    }

    // MARK: - Style helpers

    private var ringColor: Color {
        if isPaused { return Color.amachTextSecondary }
        if isRecovery { return Color.amachTextSecondary }
        return Color.amachPrimary
    }

    private var haloColor: Color {
        if isPaused || isRecovery { return Color.amachTextSecondary }
        return Color.amachPrimary
    }

    private var ringGlowRadius: CGFloat {
        // Glow swells at inhale peak.
        let breath = (pacerState.ringScale - 0.6) / 0.8
        let intensity = max(0, min(1, breath))
        return 4 + 8 * intensity
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double {
        min(max(self, lo), hi)
    }
}
