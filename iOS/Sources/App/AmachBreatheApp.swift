import SwiftUI
import Combine
import AmachBreatheShared

@main
struct AmachBreatheApp: App {

    @StateObject private var walletService = WalletService.shared
    @StateObject private var sessionService = SessionService()
    @StateObject private var watchConnectivity: WatchConnectivityService
    @StateObject private var calibrationStore: CalibrationStore
    @StateObject private var calibrationService: CalibrationService
    @StateObject private var settingsService = AppSettingsService()

    private var cancellables = Set<AnyCancellable>()

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
                .task { wireAll() }
                .onReceive(walletService.$isConnected) { connected in
                    handleWalletConnectionChange(connected: connected)
                }
                .onReceive(walletService.$encryptionKey) { key in
                    guard let key else { return }
                    Task { await sessionService.syncPending(encryptionKey: key) }
                }
        }
    }

    // MARK: - Wiring

    @MainActor
    private func wireAll() {
        watchConnectivity.onSessionReceived = { record in
            sessionService.save(record)
            // Auto-sync newly received session if wallet is available
            if let key = walletService.encryptionKey {
                Task { await sessionService.syncPending(encryptionKey: key) }
            }
        }
        watchConnectivity.onCalibrationReceived = { result in
            calibrationStore.save(result: result)
        }
        watchConnectivity.onWalletStateRequested = {
            watchConnectivity.sendWalletState(
                isConnected: walletService.isConnected,
                walletAddress: walletService.address)
        }
        // Push initial wallet state to Watch
        watchConnectivity.updateWalletApplicationContext(
            isConnected: walletService.isConnected,
            walletAddress: walletService.address)
    }

    private func handleWalletConnectionChange(connected: Bool) {
        watchConnectivity.sendWalletState(
            isConnected: connected,
            walletAddress: walletService.address)
        if !connected { return }
        // Restore cloud sessions on first connect (new device or re-login)
        if let key = walletService.encryptionKey {
            Task {
                try? await sessionService.restoreFromStorj(encryptionKey: key)
            }
        }
    }
}
