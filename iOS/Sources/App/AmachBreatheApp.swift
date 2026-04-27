import SwiftUI
import AmachBreatheShared

@main
struct AmachBreatheApp: App {

    @StateObject private var walletService = WalletService.shared
    @StateObject private var sessionService = SessionService()
    @StateObject private var watchConnectivity: WatchConnectivityService
    @StateObject private var calibrationStore: CalibrationStore
    @StateObject private var calibrationService: CalibrationService
    @StateObject private var settingsService = AppSettingsService()

    init() {
        WalletService.shared.initializePrivy()
        let store = CalibrationStore()
        let watch = WatchConnectivityService()
        let cal = CalibrationService(watchService: watch, store: store)
        _calibrationStore = StateObject(wrappedValue: store)
        _watchConnectivity = StateObject(wrappedValue: watch)
        _calibrationService = StateObject(wrappedValue: cal)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(walletService)
                .environmentObject(sessionService)
                .environmentObject(watchConnectivity)
                .environmentObject(calibrationStore)
                .environmentObject(calibrationService)
                .environmentObject(settingsService)
                .task { wireConnectivity() }
        }
    }

    @MainActor
    private func wireConnectivity() {
        watchConnectivity.onSessionReceived = { record in
            sessionService.save(record)
        }
        watchConnectivity.onCalibrationReceived = { result in
            calibrationStore.save(result: result)
        }
    }
}
