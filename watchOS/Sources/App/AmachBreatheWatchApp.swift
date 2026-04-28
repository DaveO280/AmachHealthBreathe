import SwiftUI
import AmachBreatheShared

@main
struct AmachBreatheWatchApp: App {

    @StateObject private var runner = WatchSessionRunner()
    @StateObject private var calibrationRunner = WatchCalibrationRunner()

    var body: some Scene {
        WindowGroup {
            SessionView()
                .environmentObject(runner)
                .environmentObject(calibrationRunner)
                .onAppear { runner.calibrationRunner = calibrationRunner }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    // MARK: - Complication deep link

    @MainActor
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "amachbreathe", url.host == "quickstart" else { return }
        guard runner.phase == .idle else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let duration = components?.queryItems?
            .first(where: { $0.name == "duration" })
            .flatMap { Int($0.value ?? "") } ?? 300
        Task {
            try? await runner.startSession(bpm: 5.5, durationSeconds: duration)
        }
    }
}
