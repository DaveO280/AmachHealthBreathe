import SwiftUI
import AmachBreatheShared

/// Setup screen for starting a breathing session — either on Watch or iPhone.
/// Shown as the content of the Breathe tab when no session is running.
struct SessionSetupView: View {

    @EnvironmentObject private var calibrationStore: CalibrationStore
    @EnvironmentObject private var watchConnectivity: WatchConnectivityService
    @EnvironmentObject private var runner: iPhoneSessionRunner
    @EnvironmentObject private var settingsService: AppSettingsService

    @State private var selectedDuration: Int = 300     // seconds
    @State private var selectedRatio: BreathRatio = .fourToSix
    @State private var watchSentConfirmation = false

    private var bpm: Double { calibrationStore.resonanceBPM }
    private var isCalibrated: Bool { calibrationStore.record != nil }

    var body: some View {
        ZStack {
            Color.amachBg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: AmachSpacing.lg) {
                    header
                        .padding(.top, AmachSpacing.xl)

                    bpmCard
                    durationPicker
                    ratioPicker

                    ctaSection

                    Spacer(minLength: AmachSpacing.xxl)
                }
                .padding(.horizontal, AmachSpacing.screenEdge)
            }
        }
        .onChange(of: settingsService.settings.defaultRatio) { _, ratio in
            selectedRatio = ratio
        }
        .onAppear {
            selectedRatio = settingsService.settings.defaultRatio
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: AmachSpacing.xs) {
            Image(systemName: AmachIcon.breathe)
                .font(.system(size: AmachType.iconHero))
                .foregroundStyle(Color.amachPrimary)
            Text("Breathe")
                .font(AmachType.h1)
                .foregroundStyle(Color.amachTextPrimary)
            Text("Resonant breathing, calibrated to you.")
                .font(AmachType.caption)
                .foregroundStyle(Color.amachTextSecondary)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - BPM card

    private var bpmCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Breath Rate")
                    .font(AmachType.tiny)
                    .foregroundStyle(Color.amachTextSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", bpm))
                        .font(AmachType.metricValue())
                        .foregroundStyle(Color.amachTextPrimary)
                    Text("BPM")
                        .font(AmachType.caption)
                        .foregroundStyle(Color.amachTextSecondary)
                    if !isCalibrated {
                        Text("(default)")
                            .font(AmachType.tiny)
                            .foregroundStyle(Color.amachTextTertiary)
                    }
                }
            }
            Spacer()
            if !isCalibrated {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(Color.amachPrimary)
                    Text("Calibrate\nfor best results")
                        .font(AmachType.tiny)
                        .foregroundStyle(Color.amachTextSecondary)
                        .multilineTextAlignment(.trailing)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.amachPrimary)
            }
        }
        .padding(AmachSpacing.md)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.card))
    }

    // MARK: - Duration picker

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: AmachSpacing.sm) {
            Text("Duration")
                .font(AmachType.h3)
                .foregroundStyle(Color.amachTextPrimary)
            HStack(spacing: AmachSpacing.sm) {
                ForEach([(5, 300), (10, 600), (15, 900)], id: \.1) { label, seconds in
                    Button {
                        selectedDuration = seconds
                    } label: {
                        Text("\(label) min")
                            .font(AmachType.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(selectedDuration == seconds
                                        ? Color.amachPrimary
                                        : Color.amachSurface)
                            .foregroundStyle(selectedDuration == seconds
                                             ? Color.white
                                             : Color.amachTextSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
                    }
                }
            }
        }
    }

    // MARK: - Ratio picker

    private var ratioPicker: some View {
        VStack(alignment: .leading, spacing: AmachSpacing.sm) {
            Text("Inhale : Exhale")
                .font(AmachType.h3)
                .foregroundStyle(Color.amachTextPrimary)
            HStack(spacing: AmachSpacing.sm) {
                ForEach(BreathRatio.allCases, id: \.self) { ratio in
                    Button {
                        selectedRatio = ratio
                    } label: {
                        Text(ratio.displayLabel)
                            .font(AmachType.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(selectedRatio == ratio
                                        ? Color.amachPrimary
                                        : Color.amachSurface)
                            .foregroundStyle(selectedRatio == ratio
                                             ? Color.white
                                             : Color.amachTextSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
                    }
                }
            }
        }
    }

    // MARK: - CTA section

    private var ctaSection: some View {
        VStack(spacing: AmachSpacing.sm) {
            if watchSentConfirmation {
                HStack(spacing: AmachSpacing.sm) {
                    Image(systemName: "applewatch")
                        .foregroundStyle(Color.amachPrimary)
                    Text("Session started on Apple Watch")
                        .font(AmachType.caption)
                        .foregroundStyle(Color.amachTextPrimary)
                }
                .padding(AmachSpacing.md)
                .frame(maxWidth: .infinity)
                .background(Color.amachPrimary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AmachRadius.card))
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if watchConnectivity.isWatchReachable {
                // Primary: send to Watch
                Button {
                    watchConnectivity.sendStartSession(
                        bpm: bpm,
                        durationSeconds: selectedDuration,
                        ratio: selectedRatio)
                    AmachHaptics.success()
                    withAnimation(AmachAnimation.normal) { watchSentConfirmation = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation(AmachAnimation.normal) { watchSentConfirmation = false }
                    }
                } label: {
                    Label("Start on Watch", systemImage: "applewatch")
                        .font(AmachType.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.amachPrimary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
                }

                // Secondary: run on iPhone
                Button {
                    runner.startSession(bpm: bpm, durationSeconds: selectedDuration, ratio: selectedRatio)
                } label: {
                    Text("Run on iPhone instead")
                        .font(AmachType.caption)
                        .foregroundStyle(Color.amachTextSecondary)
                        .frame(height: 44)
                }
            } else {
                // Primary: run on iPhone
                Button {
                    runner.startSession(bpm: bpm, durationSeconds: selectedDuration, ratio: selectedRatio)
                } label: {
                    Text("Start on iPhone")
                        .font(AmachType.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.amachPrimary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
                }

                // Footnote: Watch not connected
                Text("Running on iPhone — HRV tracking requires Apple Watch")
                    .font(AmachType.tiny)
                    .foregroundStyle(Color.amachTextTertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
