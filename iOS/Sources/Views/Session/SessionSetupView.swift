import SwiftUI
import AmachBreatheShared

/// Setup screen for starting a breathing session — either on Watch or iPhone.
/// Shown as the content of the Breathe tab when no session is running.
struct SessionSetupView: View {

    @EnvironmentObject private var calibrationStore: CalibrationStore
    @EnvironmentObject private var watchConnectivity: WatchConnectivityService
    @EnvironmentObject private var runner: iPhoneSessionRunner
    @EnvironmentObject private var settingsService: AppSettingsService
    @EnvironmentObject private var watchCompanionAudio: WatchCompanionAudioService

    @State private var selectedDuration: Int = 300     // seconds
    @State private var selectedRatio: BreathRatio = .fourToSix
    @State private var audioBreathTrackingEnabled = false
    @State private var watchSentConfirmation = false
    @State private var showTutorial = false

    private var bpm: Double { calibrationStore.resonanceBPM }
    private var isCalibrated: Bool { calibrationStore.record != nil }

    var body: some View {
        ZStack {
            Color.amachBg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: AmachSpacing.lg) {
                    header
                        .padding(.top, AmachSpacing.xl)

                    tutorialCard
                    bpmCard
                    durationPicker
                    ratioPicker
                    watchCompanionAudioOption
                    iPhoneAudioTrackingOption

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
        .alert(
            "Microphone access needed",
            isPresented: Binding(
                get: { watchCompanionAudio.showPermissionDeniedAlert },
                set: { if !$0 { watchCompanionAudio.dismissPermissionAlert() } }
            )
        ) {
            Button("OK", role: .cancel) { watchCompanionAudio.dismissPermissionAlert() }
        } message: {
            Text("Allow microphone access in Settings to track breath audio during Watch sessions. Your watch session will continue without audio metrics.")
        }
        .sheet(isPresented: $showTutorial) {
            BreatheTutorialSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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

    private var tutorialCard: some View {
        Button {
            showTutorial = true
        } label: {
            HStack(spacing: AmachSpacing.md) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.amachPrimary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Quick tutorial")
                        .font(AmachType.h3)
                        .foregroundStyle(Color.amachTextPrimary)
                    Text("Learn the circle, coherence, and why this pace works.")
                        .font(AmachType.caption)
                        .foregroundStyle(Color.amachTextSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.amachTextTertiary)
            }
            .padding(AmachSpacing.md)
            .background(Color.amachSurface)
            .clipShape(RoundedRectangle(cornerRadius: AmachRadius.card))
        }
        .buttonStyle(.plain)
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

    private var watchCompanionAudioOption: some View {
        VStack(alignment: .leading, spacing: AmachSpacing.xs) {
            Toggle(isOn: Binding(
                get: { settingsService.settings.watchCompanionAudioTrackingEnabled },
                set: { settingsService.updateWatchCompanionAudioTracking($0) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: AmachSpacing.xs) {
                        Text("Use iPhone mic during Watch sessions")
                            .font(AmachType.h3)
                            .foregroundStyle(Color.amachTextPrimary)
                        Text("Beta")
                            .font(AmachType.tiny.weight(.semibold))
                            .foregroundStyle(Color.amachPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.amachPrimary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Text("Keep the phone nearby, unlocked, and in a quiet room. Raw audio is not stored. Works with sessions started on the watch or from this screen.")
                        .font(AmachType.tiny)
                        .foregroundStyle(Color.amachTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(AmachSpacing.md)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.card))
    }

    private var iPhoneAudioTrackingOption: some View {
        VStack(alignment: .leading, spacing: AmachSpacing.xs) {
            Toggle(isOn: $audioBreathTrackingEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Audio breath tracking (iPhone session)")
                        .font(AmachType.h3)
                        .foregroundStyle(Color.amachTextPrimary)
                    Text("Optional estimate when you run the session on iPhone instead of Watch.")
                        .font(AmachType.tiny)
                        .foregroundStyle(Color.amachTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(AmachSpacing.md)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.card))
    }

    // MARK: - CTA section

    private var ctaSection: some View {
        VStack(spacing: AmachSpacing.sm) {
            if watchSentConfirmation {
                HStack(spacing: AmachSpacing.sm) {
                    Image(systemName: "applewatch")
                        .foregroundStyle(Color.amachPrimary)
                    Text(watchCompanionConfirmationText)
                        .font(AmachType.caption)
                        .foregroundStyle(Color.amachTextPrimary)
                }
                .padding(AmachSpacing.md)
                .frame(maxWidth: .infinity)
                .background(Color.amachPrimary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AmachRadius.card))
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if watchConnectivity.isWatchReachable {
                Button {
                    startWatchSession()
                } label: {
                    Label("Start on Watch", systemImage: "applewatch")
                        .font(AmachType.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.amachPrimary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
                }

                Button {
                    runner.startSession(
                        bpm: bpm,
                        durationSeconds: selectedDuration,
                        ratio: selectedRatio,
                        audioBreathTrackingEnabled: audioBreathTrackingEnabled)
                } label: {
                    Text("Run on iPhone instead")
                        .font(AmachType.caption)
                        .foregroundStyle(Color.amachTextSecondary)
                        .frame(height: 44)
                }
            } else {
                Button {
                    runner.startSession(
                        bpm: bpm,
                        durationSeconds: selectedDuration,
                        ratio: selectedRatio,
                        audioBreathTrackingEnabled: audioBreathTrackingEnabled)
                } label: {
                    Text("Start on iPhone")
                        .font(AmachType.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.amachPrimary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
                }

                Text("Running on iPhone — HRV tracking requires Apple Watch")
                    .font(AmachType.tiny)
                    .foregroundStyle(Color.amachTextTertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var watchCompanionConfirmationText: String {
        if settingsService.settings.watchCompanionAudioTrackingEnabled {
            return "Session started on Apple Watch — keep iPhone nearby for breath audio"
        }
        return "Session started on Apple Watch"
    }

    private func startWatchSession() {
        let companion = settingsService.settings.watchCompanionAudioTrackingEnabled
        let sessionId = watchConnectivity.sendStartSession(
            bpm: bpm,
            durationSeconds: selectedDuration,
            ratio: selectedRatio,
            companionAudioEnabled: companion
        )
        watchCompanionAudio.armForPhoneInitiatedWatchStart(
            sessionId: sessionId,
            bpm: bpm,
            companionEnabled: companion
        )
        AmachHaptics.success()
        withAnimation(AmachAnimation.normal) { watchSentConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(AmachAnimation.normal) { watchSentConfirmation = false }
        }
    }
}

private struct BreatheTutorialSheet: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.amachBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: AmachSpacing.md) {
                        tutorialItem(
                            icon: "waveform.path",
                            title: "Resonant breathing",
                            body: "Slow breathing around 4.5 to 7 breaths per minute can synchronize heart rhythm and breath. Amach uses your calibrated rate when available, or a sensible default until you calibrate."
                        )
                        tutorialItem(
                            icon: "circle.dashed",
                            title: "Follow the circle",
                            body: "Inhale as the circle expands and exhale as it contracts. The goal is a smooth, comfortable rhythm that gives your heart rate time to rise and fall with each breath."
                        )
                        tutorialItem(
                            icon: "lungs",
                            title: "What it supports",
                            body: "This pattern encourages vagal activity and heart rate variability, helping your body shift toward a calmer, more regulated state."
                        )
                        tutorialItem(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Coherence score",
                            body: "On Apple Watch sessions, Amach samples heart rhythm during the main breathing phase and scores how strongly the HRV pattern matches your target breathing rate. Higher percentages mean stronger heart-breath synchrony."
                        )
                    }
                    .padding(AmachSpacing.screenEdge)
                    .padding(.bottom, AmachSpacing.xl)
                }
            }
            .navigationTitle("How It Works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func tutorialItem(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: AmachSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.amachPrimary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(AmachType.h3)
                    .foregroundStyle(Color.amachTextPrimary)
                Text(body)
                    .font(AmachType.body)
                    .foregroundStyle(Color.amachTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AmachSpacing.cardPadding)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.card))
    }
}
