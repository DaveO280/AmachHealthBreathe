import SwiftUI
import AmachBreatheShared

public struct SessionView: View {

    @EnvironmentObject private var runner: WatchSessionRunner

    public var body: some View {
        ZStack {
            Color.amachBg.ignoresSafeArea()

            switch runner.phase {
            case .idle:
                QuickStartView()
            case .baseline, .warmup, .main:
                ActiveSessionView()
            case .recovery:
                ActiveSessionView(isRecovery: true)
            case .reflection:
                ReflectionView()
            case .complete:
                CompletionView()
            }
        }
    }
}

// MARK: - Active breathing view

private struct ActiveSessionView: View {

    @EnvironmentObject private var runner: WatchSessionRunner
    var isRecovery: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            phaseHeader

            // Expanding ring
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.2), lineWidth: 3)
                    .frame(width: 76, height: 76)

                Circle()
                    .stroke(ringColor, lineWidth: 3)
                    .frame(width: 76, height: 76)
                    .scaleEffect(runner.pacerState.ringScale)
                    .animation(.linear(duration: 1.0 / 60.0),
                               value: runner.pacerState.ringScale)

                VStack(spacing: 1) {
                    Text(runner.pacerState.breathPhase == .inhale ? "In" : "Out")
                        .font(.caption)
                        .foregroundStyle(Color.amachTextPrimary)
                    if runner.isPaused {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.amachTextSecondary)
                    }
                }
            }

            // Metrics row
            HStack(spacing: 10) {
                metricView(label: "HRV",
                           value: String(format: "%.0f", runner.currentHRV),
                           unit: "ms")
                if !isRecovery {
                    metricView(label: "Coh.",
                               value: String(format: "%.0f%%",
                                             runner.currentCoherence * 100),
                               unit: "")
                }
            }

            // Remaining time + pause/resume
            HStack(spacing: 8) {
                if let remaining = runner.pacerState.sessionPhaseRemaining {
                    Text(timeString(remaining))
                        .font(.caption2)
                        .foregroundStyle(Color.amachTextSecondary)
                        .monospacedDigit()
                }
                Spacer()
                pauseResumeButton
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var phaseHeader: some View {
        Text(phaseName)
            .font(.caption2)
            .foregroundStyle(Color.amachTextSecondary)
    }

    private var pauseResumeButton: some View {
        Button {
            if runner.isPaused { runner.resume() } else { runner.pause() }
        } label: {
            Image(systemName: runner.isPaused ? "play.fill" : "pause.fill")
                .font(.caption2)
                .foregroundStyle(Color.amachTextSecondary)
                .frame(width: 24, height: 24)
                .background(Color.amachSurface)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var ringColor: Color {
        runner.isPaused ? Color.amachTextSecondary
            : isRecovery ? Color.amachTextSecondary
            : Color.amachPrimary
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

    private func metricView(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 1) {
            Text(value + unit)
                .font(.caption)
                .foregroundStyle(Color.amachTextPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Color.amachTextSecondary)
        }
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Reflection view

private struct ReflectionView: View {

    @EnvironmentObject private var runner: WatchSessionRunner
    @State private var rating: Int = 3

    var body: some View {
        VStack(spacing: 8) {
            Text("How was it?")
                .font(.headline)
                .foregroundStyle(Color.amachTextPrimary)

            starPicker

            Button("Done") {
                runner.submitReflection(rating: rating)
            }
            .buttonStyle(.plain)
            .font(.headline)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.amachPrimary)
            .foregroundStyle(Color.amachTextPrimary)
            .clipShape(RoundedRectangle(cornerRadius: AmachRadius.sm))
        }
        .padding(8)
    }

    private var starPicker: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating
                                     ? Color.amachPrimary
                                     : Color.amachTextSecondary)
                    .onTapGesture { rating = star }
            }
        }
    }
}

// MARK: - Completion view

private struct CompletionView: View {

    @EnvironmentObject private var runner: WatchSessionRunner

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.amachPrimary)

            Text("Complete")
                .font(.headline)
                .foregroundStyle(Color.amachTextPrimary)

            if let record = runner.completedRecord {
                VStack(spacing: 2) {
                    Text(String(format: "Coherence %.0f%%",
                                (record.coherenceScore ?? 0) * 100))
                        .font(.caption)
                        .foregroundStyle(Color.amachTextSecondary)
                    if let rating = record.reflectionRating {
                        Text(String(repeating: "★", count: rating))
                            .font(.caption2)
                            .foregroundStyle(Color.amachPrimary)
                    }
                }
            }

            Button("Done") {
                Task { await runner.stopSession() }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.amachSurface)
            .foregroundStyle(Color.amachTextPrimary)
            .clipShape(RoundedRectangle(cornerRadius: AmachRadius.sm))
        }
        .padding(8)
    }
}
