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
        isConnected   = UserDefaults.standard.bool(forKey: "com.amach.breathe.watch.walletConnected")
        walletAddress = UserDefaults.standard.string(forKey: "com.amach.breathe.watch.walletAddress")
        super.init()
        // WCSession is owned by WatchSessionRunner; WatchWalletStore only manages state persistence.
    }

    /// Ask the paired iPhone for the latest wallet state.
    public func requestWalletState() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(makeWatchMessage(type: .walletStateRequest), replyHandler: nil)
    }

    // MARK: - Internal update

    func applyState(isConnected: Bool, walletAddress: String?) {
        self.isConnected = isConnected
        self.walletAddress = walletAddress?.isEmpty == false ? walletAddress : nil
        UserDefaults.standard.set(isConnected, forKey: connectedKey)
        UserDefaults.standard.set(walletAddress ?? "", forKey: addressKey)
    }
}
