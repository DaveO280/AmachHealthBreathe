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
        VStack(spacing: 8) {
            Text(phaseName)
                .font(.caption2)
                .foregroundStyle(Color.amachTextSecondary)

            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.25), lineWidth: 3)
                    .frame(width: 80, height: 80)

                Circle()
                    .stroke(ringColor, lineWidth: 3)
                    .frame(width: 80, height: 80)
                    .scaleEffect(runner.pacerState.ringScale)
                    .animation(.linear(duration: 1.0 / 60.0), value: runner.pacerState.ringScale)

                Text(runner.pacerState.breathPhase == .inhale ? "In" : "Out")
                    .font(.caption)
                    .foregroundStyle(Color.amachTextPrimary)
            }

            HStack(spacing: 12) {
                metricView(label: "HRV", value: String(format: "%.0f", runner.currentHRV), unit: "ms")
                if !isRecovery {
                    metricView(
                        label: "Coherence",
                        value: String(format: "%.0f%%", runner.currentCoherence * 100),
                        unit: ""
                    )
                }
            }

            if let remaining = runner.pacerState.sessionPhaseRemaining {
                Text(timeString(remaining))
                    .font(.caption2)
                    .foregroundStyle(Color.amachTextSecondary)
                    .monospacedDigit()
            }
        }
        .padding(8)
    }

    private var ringColor: Color {
        isRecovery ? Color.amachTextSecondary : Color.amachPrimary
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
        VStack(spacing: 2) {
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
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Reflection view

private struct ReflectionView: View {

    @EnvironmentObject private var runner: WatchSessionRunner
    @State private var rating: Int = 3

    var body: some View {
        VStack(spacing: 10) {
            Text("How was it?")
                .font(.headline)
                .foregroundStyle(Color.amachTextPrimary)

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .foregroundStyle(star <= rating ? Color.amachPrimary : Color.amachTextSecondary)
                        .onTapGesture { rating = star }
                }
            }

            Button("Done") {
                runner.submitReflection(rating: rating)
            }
            .buttonStyle(.plain)
            .font(.headline)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.amachPrimary)
            .foregroundStyle(Color.amachTextPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(8)
    }
}

// MARK: - Completion view

private struct CompletionView: View {

    @EnvironmentObject private var runner: WatchSessionRunner

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.amachPrimary)

            Text("Session Complete")
                .font(.headline)
                .foregroundStyle(Color.amachTextPrimary)

            if let record = runner.completedRecord {
                Text(String(format: "Coherence: %.0f%%", record.coherenceScore * 100))
                    .font(.caption)
                    .foregroundStyle(Color.amachTextSecondary)
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
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(8)
    }
}
