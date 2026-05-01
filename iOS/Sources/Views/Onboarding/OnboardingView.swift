import SwiftUI
import AmachBreatheShared

/// Four-page first-launch onboarding shown as a fullScreenCover.
/// Walks the user through: the resonance concept, that everyone's frequency
/// differs, the Apple Watch requirement, and a "start calibration" CTA that
/// fires `sendStartCalibration` and marks onboarding complete.
struct OnboardingView: View {

    @EnvironmentObject private var watchConnectivity: WatchConnectivityService
    @EnvironmentObject private var onboardingService: OnboardingService

    @State private var currentPage = 0

    private let totalPages = 4

    var body: some View {
        ZStack {
            Color.amachBg.ignoresSafeArea()

            VStack(spacing: 0) {
                progressDots
                    .padding(.top, AmachSpacing.lg)

                TabView(selection: $currentPage) {
                    frequencyPage.tag(0)
                    everyoneIsDifferentPage.tag(1)
                    watchRequiredPage.tag(2)
                    startCalibrationPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)
            }
        }
    }

    // MARK: - Progress dots

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalPages, id: \.self) { i in
                Circle()
                    .fill(i == currentPage ? Color.amachPrimary : Color.amachSurface)
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut, value: currentPage)
            }
        }
    }

    // MARK: - Page 1 — Resonance concept

    private var frequencyPage: some View {
        slide {
            Image(systemName: "waveform.path")
                .font(.system(size: AmachType.iconLg, weight: .light))
                .foregroundStyle(Color.amachPrimary)
                .padding(.top, AmachSpacing.xl)
        } content: {
            VStack(spacing: AmachSpacing.md) {
                Text("Your nervous system has a frequency")
                    .font(AmachType.h1)
                    .foregroundStyle(Color.amachTextPrimary)
                    .multilineTextAlignment(.center)

                Text("Heart rate variability peaks at a specific breathing rate unique to you, typically between 4.5 and 7 breaths per minute. Breathing at your resonance frequency activates the vagus nerve, synchronises your heart and breath, and shifts your body into a state of calm coherence.")
                    .font(AmachType.body)
                    .foregroundStyle(Color.amachTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, AmachSpacing.lg)
        } cta: {
            primaryButton("Continue") { advance() }
        }
    }

    // MARK: - Page 2 — Everyone's is different

    private var everyoneIsDifferentPage: some View {
        slide {
            BPMRateRow(rates: Self.calibrationRates, peakIndex: 2)
                .padding(.top, AmachSpacing.xl)
                .padding(.horizontal, AmachSpacing.md)
        } content: {
            VStack(spacing: AmachSpacing.md) {
                Text("Everyone's is different")
                    .font(AmachType.h1)
                    .foregroundStyle(Color.amachTextPrimary)
                    .multilineTextAlignment(.center)

                Text("Most people land between 5 and 6 breaths per minute, but yours could be anywhere in the range. Amach finds it by measuring your HRV while you breathe at six different rates — about 60 seconds each — then identifies where your coherence peaks.")
                    .font(AmachType.body)
                    .foregroundStyle(Color.amachTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, AmachSpacing.lg)
        } cta: {
            primaryButton("Continue") { advance() }
        }
    }

    // MARK: - Page 3 — Apple Watch required

    private var watchRequiredPage: some View {
        slide {
            Image(systemName: "applewatch.watchface")
                .font(.system(size: AmachType.iconLg, weight: .light))
                .foregroundStyle(Color.amachPrimary)
                .padding(.top, AmachSpacing.xl)
        } content: {
            VStack(spacing: AmachSpacing.md) {
                Text("Apple Watch required")
                    .font(AmachType.h1)
                    .foregroundStyle(Color.amachTextPrimary)
                    .multilineTextAlignment(.center)

                Text("Amach Breathe uses your Apple Watch to measure HRV in real time during calibration and sessions. Make sure your watch is paired and on your wrist.")
                    .font(AmachType.body)
                    .foregroundStyle(Color.amachTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                WatchReachabilityPill(isReachable: watchConnectivity.isWatchReachable)
                    .padding(.top, AmachSpacing.sm)
            }
            .padding(.horizontal, AmachSpacing.lg)
        } cta: {
            primaryButton("Continue") { advance() }
        }
    }

    // MARK: - Page 4 — Start calibration

    private var startCalibrationPage: some View {
        slide {
            BreathingRing()
                .frame(width: 160, height: 160)
                .padding(.top, AmachSpacing.xl)
        } content: {
            VStack(spacing: AmachSpacing.md) {
                Text("Let's find your frequency")
                    .font(AmachType.h1)
                    .foregroundStyle(Color.amachTextPrimary)
                    .multilineTextAlignment(.center)

                Text("Calibration takes about 6 minutes. Sit comfortably, put your watch on, and follow the breathing coach on your watch.")
                    .font(AmachType.body)
                    .foregroundStyle(Color.amachTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, AmachSpacing.lg)
        } cta: {
            primaryButton("Start calibration") { startCalibration() }
        }
    }

    // MARK: - Slide layout

    private func slide<Hero: View, Content: View, CTA: View>(
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder content: () -> Content,
        @ViewBuilder cta: () -> CTA
    ) -> some View {
        VStack(spacing: AmachSpacing.lg) {
            hero()
            Spacer(minLength: AmachSpacing.lg)
            content()
            Spacer()
            cta()
                .padding(.horizontal, AmachSpacing.screenEdge)
                .padding(.bottom, AmachSpacing.xl)
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AmachType.h3)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.amachPrimary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
        }
    }

    // MARK: - Actions

    private func advance() {
        withAnimation { currentPage = min(currentPage + 1, totalPages - 1) }
    }

    private func startCalibration() {
        watchConnectivity.sendStartCalibration()
        onboardingService.markComplete()
    }

    // MARK: - Calibration rates

    /// The six rates that calibration sweeps. Mid-range entry is highlighted as
    /// the on-screen "your peak" example.
    private static let calibrationRates: [Double] = [4.5, 5.0, 5.5, 6.0, 6.5, 7.0]
}

// MARK: - BPM rate row (Page 2 visual)

private struct BPMRateRow: View {

    let rates: [Double]
    let peakIndex: Int

    var body: some View {
        VStack(spacing: AmachSpacing.sm) {
            HStack(spacing: 8) {
                ForEach(rates.indices, id: \.self) { i in
                    capsule(for: rates[i], isPeak: i == peakIndex)
                }
            }

            Text("your peak")
                .font(AmachType.tiny)
                .foregroundStyle(Color.amachPrimary)
                .fontWeight(.medium)
                .opacity(0.9)
                .padding(.top, AmachSpacing.xs)
        }
    }

    private func capsule(for rate: Double, isPeak: Bool) -> some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(isPeak ? Color.amachPrimary : Color.amachSurface)
                .frame(width: 36, height: 56)
                .overlay(
                    Capsule()
                        .stroke(
                            isPeak ? Color.amachPrimary : Color.amachPrimary.opacity(0.18),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: isPeak ? Color.amachPrimary.opacity(0.45) : .clear,
                    radius: isPeak ? 10 : 0
                )

            Text(String(format: "%.1f", rate))
                .font(AmachType.tiny)
                .foregroundStyle(isPeak ? Color.amachPrimary : Color.amachTextSecondary)
                .fontWeight(isPeak ? .semibold : .regular)
        }
    }
}

// MARK: - Watch reachability pill (Page 3)

private struct WatchReachabilityPill: View {

    let isReachable: Bool

    var body: some View {
        HStack(spacing: AmachSpacing.sm) {
            Circle()
                .fill(isReachable ? Color.amachSuccess : Color.amachWarning)
                .frame(width: 8, height: 8)
            Text(isReachable ? "Watch connected" : "Open Amach Breathe on your watch")
                .font(AmachType.caption)
                .fontWeight(.medium)
                .foregroundStyle(isReachable ? Color.amachSuccess : Color.amachWarning)
        }
        .padding(.horizontal, AmachSpacing.md)
        .padding(.vertical, AmachSpacing.sm)
        .background(
            (isReachable ? Color.amachSuccess : Color.amachWarning)
                .opacity(0.12)
        )
        .clipShape(Capsule())
    }
}

// MARK: - Animated breathing ring (Page 4)

/// Self-contained breathing ring for onboarding. Mirrors the BreathingCoachView
/// aesthetic from the watch (track ring + halo + animated emerald ring) but
/// drives itself off a simple repeating animation rather than the master phase
/// timer — onboarding doesn't need a real pacer.
private struct BreathingRing: View {

    @State private var inhaling = false
    @State private var phaseLabel = "Inhale"
    @State private var labelTimer: Timer?

    /// 4s in / 4s out — sits in the resonance range without committing to a
    /// specific BPM. Honors Reduce Motion by skipping the animation.
    private static let cycleSeconds: Double = 4

    var body: some View {
        let scale: CGFloat = inhaling ? 1.15 : 0.7
        let intensity: Double = inhaling ? 1.0 : 0.0

        ZStack {
            // Halo
            Circle()
                .fill(Color.amachPrimary)
                .scaleEffect(0.95 + 0.25 * scale)
                .opacity(0.18 + 0.32 * intensity)
                .blur(radius: 18)

            // Track
            Circle()
                .stroke(Color.amachPrimary.opacity(0.18), lineWidth: 2)

            // Animated ring
            Circle()
                .stroke(Color.amachPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .scaleEffect(scale)
                .shadow(color: Color.amachPrimary.opacity(0.55), radius: 4 + 8 * intensity)

            Text(phaseLabel)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.amachTextPrimary)
                .tracking(0.5)
        }
        .onAppear { start() }
        .onDisappear { labelTimer?.invalidate() }
    }

    private func start() {
        guard !AmachAccessibility.isReduceMotionEnabled() else {
            inhaling = true
            return
        }
        withAnimation(.easeInOut(duration: Self.cycleSeconds).repeatForever(autoreverses: true)) {
            inhaling = true
        }
        // Crossfade the label in sync with the cycle. Start on inhale, flip on
        // each exhale boundary.
        labelTimer = Timer.scheduledTimer(withTimeInterval: Self.cycleSeconds, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.35)) {
                    phaseLabel = (phaseLabel == "Inhale") ? "Exhale" : "Inhale"
                }
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(WatchConnectivityService())
        .environmentObject(OnboardingService())
}
