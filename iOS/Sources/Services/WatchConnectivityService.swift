import Foundation
import WatchConnectivity
import AmachBreatheShared

/// Receives BreathingSessionRecord from Apple Watch via WCSession.
@MainActor
public final class WatchConnectivityService: NSObject, ObservableObject {

    public var onSessionReceived: ((BreathingSessionRecord) -> Void)?
    public var onCalibrationReceived: ((ResonanceFrequencyResult) -> Void)?

    public override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    public func sendStartSession(bpm: Double, durationSeconds: Int) {
        guard WCSession.default.isReachable else { return }
        let cmd = StartSessionCommand(bpm: bpm, durationSeconds: durationSeconds)
        guard let message = try? makeWatchMessage(type: .startSession, payload: cmd) else { return }
        WCSession.default.sendMessage(message, replyHandler: nil)
    }

    public func sendCancelSession() {
        guard WCSession.default.isReachable else { return }
        let message: [String: Any] = [
            WatchMessageKey.type.rawValue: WatchMessageType.cancelSession.rawValue
        ]
        WCSession.default.sendMessage(message, replyHandler: nil)
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
        default: break
        }
    }
}
