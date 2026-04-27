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

    public override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - iPhone → Watch commands

    public func sendStartSession(bpm: Double, durationSeconds: Int) {
        guard WCSession.default.isReachable else { return }
        let cmd = StartSessionCommand(bpm: bpm, durationSeconds: durationSeconds)
        guard let message = try? makeWatchMessage(type: .startSession, payload: cmd) else { return }
        WCSession.default.sendMessage(message, replyHandler: nil)
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
    ) { }

    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) { }
    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
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
