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
                rateBreakdown
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

    // MARK: - Per-rate HRV breakdown

    /// One row per candidate rate: BPM label + horizontal coherence bar +
    /// percentage. The winning rate is filled in emerald, others use a faded
    /// emerald. Scores in `record.scores` are normalized 0–1 against the
    /// winning rate's raw amplitude (see `CalibrationEngine.findResonance`).
    private var rateBreakdown: some View {
        let bpms = CalibrationEngine.candidateBPMs

        return VStack(spacing: 3) {
            Text("HRV coherence")
                .font(.system(size: 9))
                .foregroundStyle(Color.amachTextTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(bpms, id: \.self) { bpm in
                rateRow(bpm: bpm,
                        score: record.scores[bpm] ?? 0,
                        isWinner: abs(bpm - record.resonanceBPM) < 0.01)
            }
        }
    }

    private func rateRow(bpm: Double, score: Double, isWinner: Bool) -> some View {
        let labelColor = isWinner
            ? Color.amachPrimary
            : Color.amachTextSecondary
        let barFill = isWinner
            ? Color.amachPrimary
            : Color.amachPrimary.opacity(0.35)
        let barTrack = Color.amachTextTertiary.opacity(0.2)
        let pct = Int((score * 100).rounded())

        return HStack(spacing: 4) {
            Text(String(format: "%.1f", bpm))
                .font(.system(size: 10, weight: isWinner ? .semibold : .regular,
                              design: .rounded))
                .foregroundStyle(labelColor)
                .monospacedDigit()
                .frame(width: 22, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(barTrack)
                    Capsule()
                        .fill(barFill)
                        .frame(width: max(2, geo.size.width * CGFloat(min(max(score, 0), 1))))
                }
            }
            .frame(height: 6)

            Text("\(pct)%")
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(labelColor)
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
        }
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
