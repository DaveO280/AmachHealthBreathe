import SwiftUI
import UIKit
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
    @StateObject private var subscriptionService: SubscriptionService
    @StateObject private var onboardingService = OnboardingService()
    @StateObject private var iPhoneRunner = iPhoneSessionRunner()

    private var cancellables = Set<AnyCancellable>()

    init() {
        WalletService.shared.initializePrivy()
        let store = CalibrationStore()
        let watch = WatchConnectivityService()
        let cal = CalibrationService(watchService: watch, store: store)
        let session = SessionService()
        let sub = SubscriptionService(sessionService: session, walletService: WalletService.shared)
        _calibrationStore = StateObject(wrappedValue: store)
        _watchConnectivity = StateObject(wrappedValue: watch)
        _calibrationService = StateObject(wrappedValue: cal)
        _sessionService = StateObject(wrappedValue: session)
        _subscriptionService = StateObject(wrappedValue: sub)

        Self.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(walletService)
                .environmentObject(sessionService)
                .environmentObject(watchConnectivity)
                .environmentObject(calibrationStore)
                .environmentObject(calibrationService)
                .environmentObject(settingsService)
                .environmentObject(subscriptionService)
                .environmentObject(onboardingService)
                .environmentObject(iPhoneRunner)
                .task { await wireAll() }
                .onReceive(walletService.$isConnected) { connected in
                    handleWalletConnectionChange(connected: connected)
                }
                .onReceive(walletService.$encryptionKey) { key in
                    guard let key else { return }
                    Task { await sessionService.syncPending(encryptionKey: key) }
                }
                .sheet(isPresented: $subscriptionService.showConversionScreen) {
                    ConversionView()
                        .environmentObject(subscriptionService)
                        .environmentObject(sessionService)
                }
                .sheet(isPresented: $subscriptionService.showSyncOrSubscribePrompt) {
                    SyncOrSubscribeSheet()
                        .environmentObject(subscriptionService)
                        .presentationDetents([.height(360)])
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $subscriptionService.showSoftSupportPrompt) {
                    SoftSupportPromptView()
                        .environmentObject(subscriptionService)
                        .presentationDetents([.height(400)])
                        .presentationDragIndicator(.visible)
                }
        }
    }

    // MARK: - Wiring

    @MainActor
    private func wireAll() async {
        subscriptionService.start()
        await subscriptionService.checkAndUpdateState()
        await NotificationService.shared.refreshAuthorizationStatus()

        iPhoneRunner.onSessionComplete = { record in
            sessionService.save(record)
            if let key = walletService.encryptionKey {
                Task { await sessionService.syncPending(encryptionKey: key) }
            }
        }

        watchConnectivity.onSessionReceived = { record in
            sessionService.save(record)
            // Auto-sync newly received session if wallet is available
            if let key = walletService.encryptionKey {
                Task { await sessionService.syncPending(encryptionKey: key) }
            }
        }
        watchConnectivity.onCalibrationReceived = { result in
            calibrationStore.save(result: result)
            calibrationService.completeWithResult(result)
        }
        watchConnectivity.onCalibrationFailed = {
            calibrationService.failFromWatch()
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

    // MARK: - UIKit appearance
    //
    // Mirrors `applyTabBarAppearance()` in AmachHealth-iOS so the tab bar and
    // navigation bar render with the green-tinted dark surface, emerald
    // selected tint, and matching typography. Without this, SwiftUI falls
    // back to the default iOS materials and the tab bar reads as a generic
    // navy pill on top of our green-tinted bg.
    private static func applyAppearance() {
        let bg       = UIColor(Color.amachBg)
        let primary  = UIColor(Color.amachPrimaryBright)
        let textPri  = UIColor(Color.amachTextPrimary)
        let textSec  = UIColor(Color.amachTextSecondary)
        let hairline = UIColor(Color.amachPrimary).withAlphaComponent(0.10)

        // Tab bar
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = bg
        tab.shadowColor = hairline

        let stack = tab.stackedLayoutAppearance
        stack.selected.iconColor = primary
        stack.selected.titleTextAttributes = [.foregroundColor: primary]
        stack.normal.iconColor = textSec
        stack.normal.titleTextAttributes = [.foregroundColor: textSec]
        tab.stackedLayoutAppearance = stack
        tab.inlineLayoutAppearance = stack
        tab.compactInlineLayoutAppearance = stack

        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // Navigation bar
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = bg
        nav.shadowColor = hairline
        nav.titleTextAttributes = [
            .foregroundColor: textPri,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: textPri,
            .font: UIFont.systemFont(ofSize: 28, weight: .bold)
        ]
        nav.buttonAppearance.normal.titleTextAttributes = [.foregroundColor: primary]
        nav.backButtonAppearance.normal.titleTextAttributes = [.foregroundColor: primary]

        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = primary
    }
}
