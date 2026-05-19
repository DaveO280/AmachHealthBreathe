import SwiftUI
import AmachBreatheShared

struct ContentView: View {

    @EnvironmentObject private var subscriptionService: SubscriptionService
    @EnvironmentObject private var onboardingService: OnboardingService
    @EnvironmentObject private var runner: iPhoneSessionRunner
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            breatheTab
                .tag(0)

            HistoryView()
                .tabItem { Label("History", systemImage: "list.bullet.rectangle") }
                .tag(1)

            TrendView()
                .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(2)

            CalibrationRunnerView()
                .tabItem { Label("Calibrate", systemImage: "waveform.path.ecg") }
                .tag(3)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(4)
        }
        .tint(Color.amachPrimary)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await subscriptionService.checkAndUpdateState() }
            }
        }
        .fullScreenCover(isPresented: .constant(!onboardingService.hasCompletedOnboarding)) {
            OnboardingView()
        }
    }

    private var breatheTab: some View {
        SessionSetupView()
            .tabItem { Label("Breathe", systemImage: AmachIcon.breathe) }
            .tag(0)
            .fullScreenCover(isPresented: Binding(
                get: { runner.isRunning },
                set: { _ in }
            )) {
                iPhoneSessionView()
                    .environmentObject(runner)
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionService())
        .environmentObject(WatchConnectivityService())
        .environmentObject(CalibrationStore())
        .environmentObject(AppSettingsService())
        .environmentObject(SubscriptionService())
        .environmentObject(iPhoneSessionRunner())
        .environmentObject(WatchCompanionAudioService())
        .environmentObject({ let s = OnboardingService(); s.markComplete(); return s }())
}
