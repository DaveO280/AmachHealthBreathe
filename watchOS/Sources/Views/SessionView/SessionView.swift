import SwiftUI
import AmachBreatheShared

public struct SessionView: View {

    @EnvironmentObject private var runner: WatchSessionRunner
    @EnvironmentObject private var calibrationRunner: WatchCalibrationRunner

    public var body: some View {
        ZStack {
            Color.amachBg.ignoresSafeArea()

            if calibrationRunner.isRunning {
                CalibrationActiveView()
            } else if runner.phase == .idle,
                      case .complete(let record) = calibrationRunner.calibrationState {
                CalibrationResultView(record: record)
            } else if runner.phase == .idle,
                      case let .failed(payload) = calibrationRunner.calibrationState {
                CalibrationFailedView(payload: payload)
            } else {
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
}

// MARK: - Calibration failed view

private struct CalibrationFailedView: View {

    @EnvironmentObject private var calibrationRunner: WatchCalibrationRunner
    let payload: CalibrationFailurePayload

    var body: some View {
        VStack(spacing: WatchLayout.isCompact ? 6 : 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(Color.amachWarning)
            Text("Couldn't measure resonance")
                .font(.caption)
                .foregroundStyle(Color.amachTextPrimary)
                .multilineTextAlignment(.center)
            Text("Make sure your watch is snug and try again.")
                .font(.caption2)
                .foregroundStyle(Color.amachTextSecondary)
                .multilineTextAlignment(.center)
            Text(diagnostics)
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.amachTextTertiary)
                .multilineTextAlignment(.leading)
            Button("Try again") {
                Task {
                    await calibrationRunner.cancel()
                    await calibrationRunner.start()
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.amachPrimary)
            .foregroundStyle(Color.amachTextPrimary)
            .clipShape(RoundedRectangle(cornerRadius: AmachRadius.sm))
            Button("Close") {
                Task { await calibrationRunner.cancel() }
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(Color.amachTextSecondary)
        }
        .padding(.horizontal, WatchLayout.isCompact ? 4 : 8)
    }

    private var diagnostics: String {
        let perRate = CalibrationEngine.candidateBPMs
            .map { bpm in
                "\(String(format: "%.1f", bpm)):\(payload.perRateSampleCounts[bpm] ?? 0)"
            }
            .joined(separator: " ")
        let heartRate = payload.latestHeartRate > 0
            ? String(format: "%.0f", payload.latestHeartRate)
            : "none"
        return """
        \(payload.reason.rawValue)
        HK:\(payload.workoutWasActive ? "on" : "off") samples:\(payload.hkSampleCount) HR:\(heartRate)
        rates:\(payload.acceptedRateCount)/\(payload.totalRateCount)
        \(perRate)
        """
    }
}

// MARK: - Calibration view

private struct CalibrationActiveView: View {

    @EnvironmentObject private var calibrationRunner: WatchCalibrationRunner
    @State private var showCancelConfirm: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 6) {
                Text("Calibrating")
                    .font(.caption2)
                    .foregroundStyle(Color.amachTextSecondary)

                BreathingCoachView(
                    pacerState: calibrationRunner.pacerState,
                    isPaused: false,
                    isRecovery: false,
                    coherence: nil
                )

                if case .running(let idx, let bpm, _) = calibrationRunner.calibrationState {
                    HStack(spacing: 4) {
                        ForEach(0..<CalibrationEngine.candidateBPMs.count, id: \.self) { i in
                            Circle()
                                .fill(i < idx
                                      ? Color.amachPrimary
                                      : i == idx
                                        ? Color.amachPrimary.opacity(0.6)
                                        : Color.amachTextTertiary.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    Text(String(format: "%.1f BPM", bpm))
                        .font(.caption2)
                        .foregroundStyle(Color.amachTextSecondary)
                }
            }
            .padding(.horizontal, 8)

            cancelButton
        }
        .confirmationDialog("Cancel calibration?",
                            isPresented: $showCancelConfirm,
                            titleVisibility: .visible) {
            Button("End", role: .destructive) {
                Task { await calibrationRunner.cancel() }
            }
            Button("Keep going", role: .cancel) { }
        }
    }

    private var cancelButton: some View {
        Button {
            showCancelConfirm = true
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.amachTextSecondary)
                .frame(width: 22, height: 22)
                .background(Color.amachSurface.opacity(0.85))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel calibration")
    }
}

// MARK: - Active breathing view

private struct ActiveSessionView: View {

    @EnvironmentObject private var runner: WatchSessionRunner
    var isRecovery: Bool = false

    @State private var showEndConfirm: Bool = false

    var body: some View {
        VStack(spacing: WatchLayout.isCompact ? 4 : 6) {
            phaseHeader

            BreathingCoachView(
                pacerState: runner.pacerState,
                isPaused: runner.isPaused,
                isRecovery: isRecovery,
                coherence: isRecovery ? nil : runner.currentCoherence
            )

            // Metrics row
            HStack(spacing: WatchLayout.isCompact ? 8 : 10) {
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

            // Remaining time + pause/resume + end
            HStack(spacing: WatchLayout.isCompact ? 4 : 8) {
                if let remaining = runner.pacerState.sessionPhaseRemaining {
                    Text(timeString(remaining))
                        .font(.caption2)
                        .foregroundStyle(Color.amachTextSecondary)
                        .monospacedDigit()
                }
                Spacer()
                pauseResumeButton
                endButton
            }
        }
        .padding(.horizontal, WatchLayout.isCompact ? 4 : 8)
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

    private var endButton: some View {
        Button {
            showEndConfirm = true
        } label: {
            Image(systemName: "xmark")
                .font(.caption2)
                .foregroundStyle(Color.amachTextSecondary)
                .frame(width: 24, height: 24)
                .background(Color.amachSurface)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("End session")
        .confirmationDialog("End session?",
                            isPresented: $showEndConfirm,
                            titleVisibility: .visible) {
            Button("End", role: .destructive) {
                Task { await runner.stopSession() }
            }
            Button("Cancel", role: .cancel) { }
        }
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
