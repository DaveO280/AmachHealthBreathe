import SwiftUI
import AmachBreatheShared

/// Full-screen active session UI for iPhone-only breathing sessions.
/// Presented as a fullScreenCover from BreatheTabView while runner.isRunning == true.
struct iPhoneSessionView: View {

    @EnvironmentObject private var runner: iPhoneSessionRunner

    var body: some View {
        ZStack {
            Color.amachBg.ignoresSafeArea()
            switch runner.phase {
            case .idle:
                EmptyView()
            case .baseline, .warmup, .main, .recovery:
                ActivePhaseView()
            case .reflection:
                ReflectionView()
            case .complete:
                CompletionView()
            }
        }
    }
}

// MARK: - Active phase

private struct ActivePhaseView: View {

    @EnvironmentObject private var runner: iPhoneSessionRunner

    /// 240 pt ring per spec — fills most of the iPhone screen width.
    private let ringDiameter: CGFloat = 240

    /// Last known ringScale from an active session phase. Held in @State so a
    /// stray idle PacerState (post-stop, pre-tick) can't snap the ring back.
    @State private var displayedRingScale: Double = 1.0
    @State private var displayedBreathPhase: BreathPhase = .inhale

    var body: some View {
        VStack(spacing: AmachSpacing.xl) {
            Spacer()

            phaseLabel

            ZStack {
                haloLayer
                trackRing
                animatedRing
                centerLabel
            }
            .frame(width: ringDiameter, height: ringDiameter)
            .animation(.linear(duration: 1.0 / 60.0), value: displayedRingScale)
            .animation(.easeInOut(duration: 0.35), value: displayedBreathPhase)

            phaseTimer

            Spacer()

            controls
                .padding(.bottom, AmachSpacing.xxl)
        }
        .padding(.horizontal, AmachSpacing.screenEdge)
        .onAppear { syncFromPacerState() }
        .onChange(of: runner.pacerState.ringScale) { _, _ in syncFromPacerState() }
        .onChange(of: runner.pacerState.breathPhase) { _, _ in syncFromPacerState() }
        .onChange(of: runner.pacerState.sessionPhase) { _, _ in syncFromPacerState() }
    }

    private func syncFromPacerState() {
        guard runner.pacerState.sessionPhase.isActive else { return }
        displayedRingScale = runner.pacerState.ringScale
        displayedBreathPhase = runner.pacerState.breathPhase
    }

    // MARK: - Layers

    private var phaseLabel: some View {
        Text(phaseName)
            .font(AmachType.caption)
            .foregroundStyle(Color.amachTextSecondary)
            .tracking(2)
            .textCase(.uppercase)
            .animation(.easeInOut, value: runner.phase)
    }

    private var haloLayer: some View {
        let breath = (displayedRingScale - 0.6) / 0.8
        let intensity = max(0, min(1, breath))
        return Circle()
            .fill(haloColor)
            .frame(width: ringDiameter, height: ringDiameter)
            .scaleEffect(0.95 + 0.25 * displayedRingScale)
            .opacity(0.18 + 0.32 * intensity)
            .blur(radius: 28)
    }

    private var trackRing: some View {
        Circle()
            .stroke(ringColor.opacity(0.18), lineWidth: 3)
            .frame(width: ringDiameter, height: ringDiameter)
    }

    private var animatedRing: some View {
        Circle()
            .stroke(
                ringColor,
                style: StrokeStyle(lineWidth: 5, lineCap: .round)
            )
            .frame(width: ringDiameter, height: ringDiameter)
            .scaleEffect(displayedRingScale)
            .shadow(color: ringColor.opacity(0.55), radius: ringGlowRadius)
    }

    private var centerLabel: some View {
        ZStack {
            phaseText("Inhale")
                .opacity(displayedBreathPhase == .inhale ? 1 : 0)
            phaseText("Exhale")
                .opacity(displayedBreathPhase == .exhale ? 1 : 0)

            if runner.isPaused {
                VStack(spacing: 2) {
                    Spacer().frame(height: 36)
                    Image(systemName: "pause.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.amachTextSecondary)
                }
            }
        }
    }

    private func phaseText(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.amachTextPrimary)
            .tracking(0.5)
    }

    @ViewBuilder
    private var phaseTimer: some View {
        if let remaining = runner.pacerState.sessionPhaseRemaining {
            Text(timeString(remaining))
                .font(AmachType.metricValue(size: 20))
                .foregroundStyle(Color.amachTextSecondary)
                .monospacedDigit()
        } else {
            Color.clear.frame(height: 24)
        }
    }

    private var controls: some View {
        VStack(spacing: AmachSpacing.md) {
            Button {
                if runner.isPaused { runner.resume() } else { runner.pause() }
            } label: {
                Image(systemName: runner.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 22))
                    .frame(width: 64, height: 64)
                    .background(Color.amachSurface)
                    .foregroundStyle(Color.amachTextPrimary)
                    .clipShape(Circle())
            }

            Button {
                runner.submitReflection(rating: nil)
            } label: {
                Text("End Session")
                    .font(AmachType.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.amachSurface)
                    .foregroundStyle(Color.amachTextPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: AmachRadius.md)
                            .stroke(Color.amachPrimary.opacity(0.30), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Style helpers

    private var ringColor: Color {
        if runner.isPaused { return Color.amachTextSecondary }
        if case .recovery = runner.phase { return Color.amachTextSecondary }
        return Color.amachPrimary
    }

    private var haloColor: Color {
        if runner.isPaused { return Color.amachTextSecondary }
        if case .recovery = runner.phase { return Color.amachTextSecondary }
        return Color.amachPrimary
    }

    private var ringGlowRadius: CGFloat {
        let breath = (displayedRingScale - 0.6) / 0.8
        let intensity = max(0, min(1, breath))
        return 8 + 16 * intensity
    }

    private var phaseName: String {
        switch runner.phase {
        case .baseline: return "Settling"
        case .warmup:   return "Warm Up"
        case .main:     return "Breathe"
        case .recovery: return "Recovery"
        default:        return ""
        }
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Reflection

private struct ReflectionView: View {

    @EnvironmentObject private var runner: iPhoneSessionRunner
    @State private var rating: Int = 3

    var body: some View {
        VStack(spacing: AmachSpacing.lg) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: AmachType.iconHero))
                .foregroundStyle(Color.amachPrimary)

            VStack(spacing: AmachSpacing.xs) {
                Text("Session complete")
                    .font(AmachType.h2)
                    .foregroundStyle(Color.amachTextPrimary)
                Text("How do you feel?")
                    .font(AmachType.caption)
                    .foregroundStyle(Color.amachTextSecondary)
            }

            HStack(spacing: AmachSpacing.md) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: 32))
                        .foregroundStyle(star <= rating ? Color.amachGold : Color.amachTextTertiary)
                        .onTapGesture {
                            rating = star
                            AmachHaptics.toggle()
                        }
                }
            }

            Spacer()

            VStack(spacing: AmachSpacing.sm) {
                Button {
                    runner.submitReflection(rating: rating)
                } label: {
                    Text("Done")
                        .font(AmachType.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.amachPrimary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
                }

                Button {
                    runner.submitReflection(rating: nil)
                } label: {
                    Text("Skip")
                        .font(AmachType.caption)
                        .foregroundStyle(Color.amachTextSecondary)
                        .frame(height: 44)
                }
            }
            .padding(.horizontal, AmachSpacing.screenEdge)
            .padding(.bottom, AmachSpacing.xxl)
        }
    }
}

// MARK: - Completion

private struct CompletionView: View {

    @EnvironmentObject private var runner: iPhoneSessionRunner

    var body: some View {
        VStack(spacing: AmachSpacing.lg) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: AmachType.iconHero))
                .foregroundStyle(Color.amachPrimary)

            VStack(spacing: AmachSpacing.xs) {
                Text("Done")
                    .font(AmachType.h1)
                    .foregroundStyle(Color.amachTextPrimary)
                if let record = runner.completedRecord {
                    sessionSummary(record)
                }
            }

            Spacer()

            Button {
                runner.endSession()
            } label: {
                Text("Back to Setup")
                    .font(AmachType.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.amachPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
            }
            .padding(.horizontal, AmachSpacing.screenEdge)
            .padding(.bottom, AmachSpacing.xxl)
        }
    }

    private func sessionSummary(_ record: BreathingSessionRecord) -> some View {
        HStack(spacing: AmachSpacing.md) {
            summaryTile(value: "\(record.durationSeconds / 60) min", label: "Duration")
            summaryTile(value: String(format: "%.1f", record.bpm), label: "BPM")
            summaryTile(value: record.ratio, label: "Ratio")
            if let rating = record.reflectionRating {
                summaryTile(value: String(repeating: "★", count: rating), label: "Mood")
            }
        }
        .padding(AmachSpacing.md)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.card))
        .padding(.horizontal, AmachSpacing.screenEdge)
    }

    private func summaryTile(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AmachType.h3)
                .foregroundStyle(Color.amachTextPrimary)
            Text(label)
                .font(AmachType.tiny)
                .foregroundStyle(Color.amachTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
