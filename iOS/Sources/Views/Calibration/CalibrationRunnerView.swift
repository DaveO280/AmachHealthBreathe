import SwiftUI
import Charts
import AmachBreatheShared

struct CalibrationRunnerView: View {

    @EnvironmentObject private var calibrationService: CalibrationService
    @EnvironmentObject private var calibrationStore: CalibrationStore

    @Environment(\.dismiss) private var dismiss
    @State private var showWatchPrompt = false

    private static let fastCalibrationRateSeconds: TimeInterval = 10

    var body: some View {
        NavigationStack {
            ZStack {
                Color.amachBg.ignoresSafeArea()
                VStack(spacing: 0) {
                    headerSection
                        .padding(.horizontal, AmachSpacing.md)
                        .padding(.top, AmachSpacing.sm)
                    VStack(spacing: AmachSpacing.sectionSpacing) {
                        switch calibrationService.calibrationState {
                        case .idle:
                            idleView
                        case let .running(bpm, elapsed, total):
                            runningView(bpm: bpm, elapsed: elapsed, total: total)
                        case .awaitingResult:
                            awaitingResultView
                        case let .complete(result):
                            completeView(result: result)
                        case let .failed(message, diagnostics):
                            failedView(message: message, diagnostics: diagnostics)
                        }
                    }
                    .padding(AmachSpacing.screenEdge)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: AmachSpacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                AmachBrandMark(layout: .compact)
                Text("Calibrate")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.amachTextPrimary)
            }
            Spacer()
            if case .running = calibrationService.calibrationState {
                Button {
                    calibrationService.cancel()
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(AmachType.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.amachTextSecondary)
                }
            }
        }
        .padding(.bottom, AmachSpacing.sm)
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: AmachSpacing.lg) {
            Spacer()
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: AmachType.iconLg))
                .foregroundStyle(Color.amachPrimary)
            Text("Find Your Resonance Rate")
                .font(AmachType.h2)
                .foregroundStyle(Color.amachTextPrimary)
                .multilineTextAlignment(.center)
            Text("A 6-minute test will measure your HRV at 6 different breath rates and identify the frequency that creates the strongest heart-breath resonance.")
                .font(AmachType.caption)
                .foregroundStyle(Color.amachTextSecondary)
                .multilineTextAlignment(.center)
            if let record = calibrationStore.record {
                existingResultCard(record)
            }
            Spacer()
            Button("Start Calibration") {
                if !calibrationService.startCalibration() {
                    showWatchPrompt = true
                }
            }
            .amachPrimaryButtonStyle()
            if shouldShowFastCalibration {
                Button("Fast Test Calibration") {
                    if !calibrationService.startCalibration(
                        sampleDurationPerRate: Self.fastCalibrationRateSeconds) {
                        showWatchPrompt = true
                    }
                }
                .font(AmachType.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.amachPrimary)
                Text("TestFlight debug run: about 1 minute total.")
                    .font(AmachType.tiny)
                    .foregroundStyle(Color.amachTextTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .alert("Open Watch App First", isPresented: $showWatchPrompt) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Open the Amach Breathe app on your Apple Watch, then tap Start Calibration.")
        }
    }

    private func existingResultCard(_ record: CalibrationRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current: \(record.resonanceBPM, specifier: "%.1f") BPM")
                    .font(AmachType.h3)
                    .foregroundStyle(Color.amachTextPrimary)
                if record.needsRetest {
                    Text("Retest recommended")
                        .font(AmachType.tiny)
                        .foregroundStyle(Color.amachWarning)
                } else {
                    Text("Valid for \(daysUntilRetest(record)) more days")
                        .font(AmachType.tiny)
                        .foregroundStyle(Color.amachTextSecondary)
                }
            }
            Spacer()
        }
        .padding(AmachSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .amachCard()
    }

    // MARK: - Running

    private func runningView(bpm: Double, elapsed: TimeInterval, total: TimeInterval) -> some View {
        VStack(spacing: AmachSpacing.lg) {
            Spacer()
            progressRing(elapsed: elapsed, total: total)
            VStack(spacing: AmachSpacing.sm) {
                Text("Testing \(bpm, specifier: "%.1f") BPM")
                    .font(AmachType.h2)
                    .foregroundStyle(Color.amachTextPrimary)
                Text("Keep your Apple Watch on and breathe with the pacer")
                    .font(AmachType.caption)
                    .foregroundStyle(Color.amachTextSecondary)
                    .multilineTextAlignment(.center)
            }
            rateProgressRow(currentBPM: bpm)
            Spacer()
            Button("Cancel") {
                calibrationService.cancel()
                dismiss()
            }
            .font(AmachType.body)
            .foregroundStyle(Color.amachTextSecondary)
        }
    }

    private func progressRing(elapsed: TimeInterval, total: TimeInterval) -> some View {
        let fraction = total > 0 ? min(elapsed / total, 1.0) : 0
        let minutesLeft = Int(ceil((total - elapsed) / 60))
        return ZStack {
            Circle()
                .stroke(Color.amachTextTertiary.opacity(0.2), lineWidth: 12)
                .frame(width: 140, height: 140)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.amachPrimary, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: 140, height: 140)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: fraction)
            VStack(spacing: 2) {
                Text("\(minutesLeft)")
                    .font(.system(size: AmachType.iconBase, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.amachTextPrimary)
                Text("min left")
                    .font(AmachType.tiny)
                    .foregroundStyle(Color.amachTextSecondary)
            }
        }
    }

    private func rateProgressRow(currentBPM: Double) -> some View {
        HStack(spacing: AmachSpacing.sm) {
            ForEach(CalibrationEngine.candidateBPMs, id: \.self) { bpm in
                let isDone = bpm < currentBPM
                let isCurrent = bpm == currentBPM
                VStack(spacing: 4) {
                    Circle()
                        .fill(isDone ? Color.amachPrimary : (isCurrent ? Color.amachPrimary.opacity(0.6) : Color.amachTextTertiary.opacity(0.3)))
                        .frame(width: 12, height: 12)
                    Text(String(format: "%.1f", bpm))
                        .font(AmachType.tiny)
                        .foregroundStyle(isCurrent ? Color.amachPrimary : Color.amachTextTertiary)
                }
            }
        }
        .padding(AmachSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .amachCard()
    }

    // MARK: - Awaiting result

    private var awaitingResultView: some View {
        VStack(spacing: AmachSpacing.lg) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color.amachPrimary)
                .scaleEffect(1.4)
            VStack(spacing: AmachSpacing.sm) {
                Text("Calibration complete")
                    .font(AmachType.h2)
                    .foregroundStyle(Color.amachTextPrimary)
                Text("Analyzing your resonance frequency on Apple Watch…")
                    .font(AmachType.caption)
                    .foregroundStyle(Color.amachTextSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button("Cancel") {
                calibrationService.cancel()
                dismiss()
            }
            .font(AmachType.body)
            .foregroundStyle(Color.amachTextSecondary)
        }
    }

    // MARK: - Complete

    private func completeView(result: ResonanceFrequencyResult) -> some View {
        VStack(spacing: AmachSpacing.lg) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: AmachType.iconLg))
                .foregroundStyle(Color.amachPrimary)
            VStack(spacing: AmachSpacing.sm) {
                Text("Your Resonance Rate")
                    .font(AmachType.h2)
                    .foregroundStyle(Color.amachTextPrimary)
                Text("\(result.resonanceBPM, specifier: "%.1f") BPM")
                    .font(.system(size: AmachType.iconHero, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.amachPrimary)
                Text("This breath rate creates the strongest heart-breath synchrony for you")
                    .font(AmachType.caption)
                    .foregroundStyle(Color.amachTextSecondary)
                    .multilineTextAlignment(.center)
            }
            amplitudeChart(scores: result.scores, resonanceBPM: result.resonanceBPM)
            Spacer()
            Button("Done") { dismiss() }
                .amachPrimaryButtonStyle()
        }
    }

    private func amplitudeChart(scores: [Double: Double], resonanceBPM: Double) -> some View {
        let sorted = scores.sorted { $0.key < $1.key }
        return VStack(alignment: .leading, spacing: AmachSpacing.sm) {
            Text("HRV Amplitude by Rate")
                .font(AmachType.h3)
                .foregroundStyle(Color.amachTextPrimary)
            Chart {
                ForEach(sorted, id: \.key) { bpm, score in
                    BarMark(
                        x: .value("BPM", String(format: "%.1f", bpm)),
                        y: .value("Score", score)
                    )
                    .foregroundStyle(bpm == resonanceBPM ? Color.amachPrimary : Color.amachPrimary.opacity(0.35))
                    .cornerRadius(4)
                }
            }
            .frame(height: 140)
            .chartYAxis {
                AxisMarks { val in
                    AxisValueLabel {
                        Text(val.as(Double.self).map { String(format: "%.0f%%", $0 * 100) } ?? "")
                            .font(AmachType.tiny)
                            .foregroundStyle(Color.amachTextSecondary)
                    }
                    AxisGridLine().foregroundStyle(Color.amachTextTertiary.opacity(0.15))
                }
            }
        }
        .padding(AmachSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .amachCard()
    }

    // MARK: - Failed

    private func failedView(message: String, diagnostics: String?) -> some View {
        VStack(spacing: AmachSpacing.lg) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: AmachType.iconLg))
                .foregroundStyle(Color.amachDestructive)
            Text("Calibration Failed")
                .font(AmachType.h2)
                .foregroundStyle(Color.amachTextPrimary)
            Text(message)
                .font(AmachType.caption)
                .foregroundStyle(Color.amachTextSecondary)
                .multilineTextAlignment(.center)
            if let diagnostics {
                Text(diagnostics)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.amachTextTertiary)
                    .multilineTextAlignment(.leading)
                    .padding(AmachSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .amachCard()
            }
            Spacer()
            Button("Try Again") { calibrationService.startCalibration() }
                .amachPrimaryButtonStyle()
        }
    }

    // MARK: - Helpers

    private func daysUntilRetest(_ record: CalibrationRecord) -> Int {
        let days = Int(record.retestAfter.timeIntervalSince(Date()) / 86400)
        return max(0, days)
    }

    private var shouldShowFastCalibration: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
