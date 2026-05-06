import SwiftUI
import AmachBreatheShared

public struct QuickStartView: View {

    @EnvironmentObject private var runner: WatchSessionRunner
    @EnvironmentObject private var calibrationRunner: WatchCalibrationRunner

    @State private var selectedBPM: Double = 5.5
    @State private var selectedDuration: Int = 300
    @State private var selectedRatio: BreathRatio = .fourToSix
    @State private var isStarting: Bool = false
    @State private var isStartingCalibration: Bool = false

    private let bpmOptions: [Double] = CalibrationEngine.candidateBPMs
    private let durationOptions: [(label: String, seconds: Int)] = [
        ("5", 300), ("10", 600), ("15", 900)
    ]
    private static let fastCalibrationRateSeconds: TimeInterval = 10

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WatchLayout.isCompact ? 6 : 10) {
                    Text("Breathe")
                        .font(WatchLayout.isCompact ? .subheadline : .headline)
                        .foregroundStyle(Color.amachTextPrimary)

                    bpmPicker
                    durationPicker
                    ratioPicker
                    startButton
                    if shouldShowFastCalibration {
                        fastCalibrationButton
                    }
                }
                .padding(.horizontal, WatchLayout.isCompact ? 4 : 8)
                .padding(.bottom, 8)
            }
            .navigationTitle("")
        }
        .task { try? await runner.requestHealthKitAuthorization() }
    }

    // MARK: - Subviews

    private var bpmPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Rate", systemImage: "waveform.path.ecg")
                .font(.caption2)
                .foregroundStyle(Color.amachTextSecondary)
            Picker("BPM", selection: $selectedBPM) {
                ForEach(bpmOptions, id: \.self) { bpm in
                    Text("\(bpm, specifier: "%.1f") BPM").tag(bpm)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: WatchLayout.isCompact ? 48 : 60)
        }
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Duration (min)", systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(Color.amachTextSecondary)
            HStack(spacing: 4) {
                ForEach(durationOptions, id: \.seconds) { opt in
                    durationChip(opt.label, seconds: opt.seconds)
                }
            }
        }
    }

    private func durationChip(_ label: String, seconds: Int) -> some View {
        Button(label) { selectedDuration = seconds }
            .buttonStyle(.plain)
            .font(.caption)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AmachRadius.xs)
                    .fill(selectedDuration == seconds
                          ? Color.amachPrimary
                          : Color.amachSurface)
            )
            .foregroundStyle(Color.amachTextPrimary)
    }

    private var ratioPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Ratio", systemImage: "lungs")
                .font(.caption2)
                .foregroundStyle(Color.amachTextSecondary)
            HStack(spacing: 4) {
                ForEach(BreathRatio.allCases, id: \.self) { ratio in
                    Button(ratio.displayLabel) { selectedRatio = ratio }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: AmachRadius.xs)
                                .fill(selectedRatio == ratio
                                      ? Color.amachPrimary
                                      : Color.amachSurface)
                        )
                        .foregroundStyle(Color.amachTextPrimary)
                }
            }
        }
    }

    private var startButton: some View {
        Button {
            startSession()
        } label: {
            if isStarting {
                ProgressView().tint(Color.amachTextPrimary)
            } else {
                Text("Start")
                    .font(WatchLayout.isCompact ? .subheadline : .headline)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, WatchLayout.isCompact ? 8 : 10)
        .background(Color.amachPrimary)
        .foregroundStyle(Color.amachTextPrimary)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.sm))
        .disabled(isStarting)
    }

    private var fastCalibrationButton: some View {
        Button {
            startFastCalibration()
        } label: {
            if isStartingCalibration {
                ProgressView().tint(Color.amachTextPrimary)
            } else {
                Text("Fast Cal")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 7)
        .background(Color.amachSurface)
        .foregroundStyle(Color.amachPrimary)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.sm))
        .disabled(isStarting || isStartingCalibration)
    }

    // MARK: - Actions

    private func startSession() {
        isStarting = true
        Task {
            try? await runner.startSession(
                bpm: selectedBPM,
                durationSeconds: selectedDuration,
                ratio: selectedRatio
            )
            await MainActor.run { isStarting = false }
        }
    }

    private func startFastCalibration() {
        isStartingCalibration = true
        Task {
            calibrationRunner.sampleDurationPerRate = Self.fastCalibrationRateSeconds
            await calibrationRunner.start()
            await MainActor.run { isStartingCalibration = false }
        }
    }

    private var shouldShowFastCalibration: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
