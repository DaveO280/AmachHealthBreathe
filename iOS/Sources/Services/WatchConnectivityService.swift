import Foundation
import WatchConnectivity
import AmachBreatheShared

/// Receives BreathingSessionRecord from Apple Watch via WCSession
/// and propagates wallet state changes to the Watch.
@MainActor
public final class WatchConnectivityService: NSObject, ObservableObject {

    public var onSessionReceived: ((BreathingSessionRecord) -> Void)?
    public var onCalibrationReceived: ((ResonanceFrequencyResult) -> Void)?
    /// Set by the app root to push current wallet state when Watch requests it.
    public var onWalletStateRequested: (() -> Void)?

    @Published public var isWatchReachable: Bool = false

    public override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - iPhone → Watch commands

    public func sendStartSession(bpm: Double, durationSeconds: Int, ratio: BreathRatio = .fourToSix) {
        guard WCSession.default.isReachable else { return }
        let cmd = StartSessionCommand(bpm: bpm, durationSeconds: durationSeconds, ratio: ratio.rawValue)
        guard let message = try? makeWatchMessage(type: .startSession, payload: cmd) else { return }
        WCSession.default.sendMessage(message, replyHandler: nil)
    }

    /// Sends a start-calibration command to the Watch. Returns false if Watch isn't reachable —
    /// caller should prompt the user to open the Watch app.
    @discardableResult
    public func sendStartCalibration() -> Bool {
        guard WCSession.default.isReachable else { return false }
        WCSession.default.sendMessage(makeWatchMessage(type: .startCalibration), replyHandler: nil)
        return true
    }

    public func sendCancelSession() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(makeWatchMessage(type: .cancelSession), replyHandler: nil)
    }

    /// Push current wallet state to Watch via real-time message (Watch reachable).
    public func sendWalletState(isConnected: Bool, walletAddress: String?) {
        guard WCSession.default.isReachable else {
            updateWalletApplicationContext(isConnected: isConnected, walletAddress: walletAddress)
            return
        }
        let msg = WalletStateMessage(isConnected: isConnected, walletAddress: walletAddress)
        guard let message = try? makeWatchMessage(type: .walletState, payload: msg) else { return }
        WCSession.default.sendMessage(message, replyHandler: nil)
        // Also update context so Watch gets it on next launch if currently unreachable
        updateWalletApplicationContext(isConnected: isConnected, walletAddress: walletAddress)
    }

    /// Transfer wallet state via application context (persists across Watch sessions).
    public func updateWalletApplicationContext(isConnected: Bool, walletAddress: String?) {
        let context: [String: Any] = [
            "walletConnected": isConnected,
            "walletAddress": walletAddress ?? ""
        ]
        try? WCSession.default.updateApplicationContext(context)
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in self?.refreshReachability() }
    }

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.refreshReachability() }
    }

    private func refreshReachability() {
        guard WCSession.isSupported() else { isWatchReachable = false; return }
        isWatchReachable = WCSession.default.activationState == .activated
            && WCSession.default.isWatchAppInstalled
            && WCSession.default.isReachable
    }

    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) { }
    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        handleIncoming(message)
    }

    // Background-delivery fallback for calibration results when iPhone isn't foreground
    nonisolated public func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        handleIncoming(userInfo)
    }

    nonisolated private func handleIncoming(_ message: [String: Any]) {
        guard let type = watchMessageType(from: message) else { return }
        switch type {
        case .sessionComplete:
            guard let record = try? decodeWatchPayload(BreathingSessionRecord.self, from: message) else { return }
            Task { @MainActor [weak self] in self?.onSessionReceived?(record) }
        case .calibrationResult:
            guard let result = try? decodeWatchPayload(ResonanceFrequencyResult.self, from: message) else { return }
            Task { @MainActor [weak self] in self?.onCalibrationReceived?(result) }
        case .walletStateRequest:
            Task { @MainActor [weak self] in self?.onWalletStateRequested?() }
        default:
            break
        }
    }
}
