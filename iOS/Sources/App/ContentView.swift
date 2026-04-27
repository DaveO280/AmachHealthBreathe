import SwiftUI
import AmachBreatheShared

struct ContentView: View {

    @EnvironmentObject private var subscriptionService: SubscriptionService
    @EnvironmentObject private var onboardingService: OnboardingService
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "list.bullet.rectangle")
                }
                .tag(0)

            TrendView()
                .tabItem {
                    Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(1)

            CalibrationRunnerView()
                .tabItem {
                    Label("Calibrate", systemImage: "waveform.path.ecg")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
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
}

#Preview {
    ContentView()
        .environmentObject(SessionService())
        .environmentObject(CalibrationService())
        .environmentObject(CalibrationStore())
        .environmentObject(AppSettingsService())
        .environmentObject(SubscriptionService())
        .environmentObject({ let s = OnboardingService(); s.markComplete(); return s }())
}
