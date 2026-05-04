import SwiftUI
import AmachBreatheShared

/// Shown when WatchCalibrationRunner finishes with `.complete(record)`.
/// Displays the winning resonance BPM, a compact bar of relative coherence
/// across all 6 candidate rates, and actions to start a session at the
/// recommended rate or run calibration again.
struct CalibrationResultView: View {

    let record: CalibrationRecord

    @EnvironmentObject private var runner: WatchSessionRunner
    @EnvironmentObject private var calibrationRunner: WatchCalibrationRunner

    @State private var isStarting: Bool = false

    private static let defaultDurationSeconds: Int = 300

    var body: some View {
        ScrollView {
            VStack(spacing: WatchLayout.isCompact ? 6 : 10) {
                headline
                bpmDisplay
                scoreBars
                beginButton
                recalibrateButton
            }
            .padding(.horizontal, WatchLayout.isCompact ? 4 : 8)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Headline

    private var headline: some View {
        Text("Your resonance frequency")
            .font(.caption2)
            .foregroundStyle(Color.amachTextSecondary)
            .multilineTextAlignment(.center)
    }

    private var bpmDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(String(format: "%.1f", record.resonanceBPM))
                .font(.system(size: WatchLayout.isCompact ? 28 : 34,
                              weight: .bold, design: .rounded))
                .foregroundStyle(Color.amachTextPrimary)
                .monospacedDigit()
            Text("BPM")
                .font(.caption)
                .foregroundStyle(Color.amachTextSecondary)
        }
        .shadow(color: Color.amachPrimary.opacity(0.45), radius: 8)
    }

    // MARK: - Score bars

    private var scoreBars: some View {
        let bpms = CalibrationEngine.candidateBPMs
        let maxBarHeight: CGFloat = 32

        return VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(bpms, id: \.self) { bpm in
                    let score = record.scores[bpm] ?? 0
                    let isWinner = abs(bpm - record.resonanceBPM) < 0.01
                    Capsule()
                        .fill(barColor(isWinner: isWinner))
                        .frame(width: 10,
                               height: max(3, CGFloat(score) * maxBarHeight))
                        .shadow(
                            color: isWinner
                                ? Color.amachPrimary.opacity(0.55)
                                : .clear,
                            radius: isWinner ? 4 : 0
                        )
                }
            }
            .frame(height: maxBarHeight, alignment: .bottom)

            HStack {
                Text(String(format: "%.1f", bpms.first ?? 0))
                Spacer()
                Text(String(format: "%.1f", bpms.last ?? 0))
            }
            .font(.system(size: 9))
            .foregroundStyle(Color.amachTextTertiary)
            .frame(maxWidth: 84)
        }
    }

    private func barColor(isWinner: Bool) -> Color {
        isWinner
            ? Color.amachPrimary
            : Color.amachPrimary.opacity(0.35)
    }

    // MARK: - Buttons

    private var beginButton: some View {
        Button {
            beginSession()
        } label: {
            if isStarting {
                ProgressView().tint(Color.amachTextPrimary)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Begin session")
                    .font(WatchLayout.isCompact ? .subheadline : .headline)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, WatchLayout.isCompact ? 8 : 10)
        .background(Color.amachPrimary)
        .foregroundStyle(Color.amachTextPrimary)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.sm))
        .shadow(color: Color.amachPrimary.opacity(0.40), radius: 8, y: 2)
        .disabled(isStarting)
    }

    private var recalibrateButton: some View {
        Button {
            recalibrate()
        } label: {
            Text("Recalibrate")
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
        .background(Color.amachSurface)
        .foregroundStyle(Color.amachTextSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.sm))
        .disabled(isStarting)
    }

    // MARK: - Actions

    private func beginSession() {
        isStarting = true
        Task {
            try? await runner.startSession(
                bpm: record.resonanceBPM,
                durationSeconds: Self.defaultDurationSeconds,
                ratio: .fourToSix
            )
            await MainActor.run { isStarting = false }
        }
    }

    private func recalibrate() {
        Task {
            await calibrationRunner.cancel()
            await calibrationRunner.start()
        }
    }
}
