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

    private let ringDiameter: CGFloat = 200

    var body: some View {
        VStack(spacing: AmachSpacing.xl) {
            Spacer()

            // Phase label
            Text(phaseName)
                .font(AmachType.caption)
                .foregroundStyle(Color.amachTextSecondary)
                .animation(.easeInOut, value: runner.phase)

            // Breathing ring
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.15), lineWidth: 5)
                    .frame(width: ringDiameter, height: ringDiameter)

                Circle()
                    .stroke(ringColor, lineWidth: 5)
                    .frame(width: ringDiameter, height: ringDiameter)
                    .scaleEffect(runner.pacerState.ringScale)
                    .animation(.linear(duration: 1.0 / 60.0),
                               value: runner.pacerState.ringScale)

                VStack(spacing: AmachSpacing.xs) {
                    Text(runner.pacerState.breathPhase == .inhale ? "inhale" : "exhale")
                        .font(AmachType.h3)
                        .foregroundStyle(Color.amachTextPrimary)
                    if runner.isPaused {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.amachTextSecondary)
                    }
                }
            }

            // Phase timer
            if let remaining = runner.pacerState.sessionPhaseRemaining {
                Text(timeString(remaining))
                    .font(AmachType.metricValue(size: 18))
                    .foregroundStyle(Color.amachTextSecondary)
                    .monospacedDigit()
            }

            Spacer()

            // Controls
            HStack(spacing: AmachSpacing.lg) {
                Button {
                    if runner.isPaused { runner.resume() } else { runner.pause() }
                } label: {
                    Image(systemName: runner.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 20))
                        .frame(width: 56, height: 56)
                        .background(Color.amachSurface)
                        .foregroundStyle(Color.amachTextPrimary)
                        .clipShape(Circle())
                }

                Button {
                    runner.submitReflection(rating: nil)
                } label: {
                    Text("End")
                        .font(AmachType.caption.weight(.semibold))
                        .frame(width: 80, height: 56)
                        .background(Color.amachSurface)
                        .foregroundStyle(Color.amachTextSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
                }
            }
            .padding(.bottom, AmachSpacing.xxl)
        }
    }

    private var ringColor: Color {
        if runner.isPaused { return Color.amachTextSecondary }
        if case .recovery = runner.phase { return Color.amachTextSecondary }
        return Color.amachPrimary
    }

    private var phaseName: String {
        switch runner.phase {
        case .baseline: return "Baseline"
        case .warmup:   return "Warm Up"
        case .main:     return "Breathing"
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
