import Foundation
import WatchConnectivity
import AmachBreatheShared

/// Receives wallet connection state from the paired iPhone via WCSession.
/// Persists state in UserDefaults so it survives Watch app restarts.
/// Watch sessions use this to know whether the user's iPhone is connected.
@MainActor
public final class WatchWalletStore: NSObject, ObservableObject {

    public static let shared = WatchWalletStore()

    @Published public private(set) var isConnected = false
    @Published public private(set) var walletAddress: String?

    private let connectedKey = "com.amach.breathe.watch.walletConnected"
    private let addressKey   = "com.amach.breathe.watch.walletAddress"

    private override init() {
        isConnected  = UserDefaults.standard.bool(forKey: "com.amach.breathe.watch.walletConnected")
        walletAddress = UserDefaults.standard.string(forKey: "com.amach.breathe.watch.walletAddress")
        super.init()
        activateSession()
    }

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Ask the paired iPhone for the latest wallet state.
    public func requestWalletState() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(makeWatchMessage(type: .walletStateRequest), replyHandler: nil)
    }

    // MARK: - Internal update

    fileprivate func applyState(isConnected: Bool, walletAddress: String?) {
        self.isConnected = isConnected
        self.walletAddress = walletAddress?.isEmpty == false ? walletAddress : nil
        UserDefaults.standard.set(isConnected, forKey: connectedKey)
        UserDefaults.standard.set(walletAddress ?? "", forKey: addressKey)
    }
}

// MARK: - WCSessionDelegate

extension WatchWalletStore: WCSessionDelegate {
    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) { }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        guard watchMessageType(from: message) == .walletState,
              let state = try? decodeWatchPayload(WalletStateMessage.self, from: message)
        else { return }
        Task { @MainActor [weak self] in
            self?.applyState(isConnected: state.isConnected, walletAddress: state.walletAddress)
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let connected = applicationContext["walletConnected"] as? Bool ?? false
        let address = applicationContext["walletAddress"] as? String
        Task { @MainActor [weak self] in
            self?.applyState(isConnected: connected, walletAddress: address)
        }
    }
}
