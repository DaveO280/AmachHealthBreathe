import Foundation
import WatchConnectivity
import AmachBreatheShared

/// Receives BreathingSessionRecord from Apple Watch via WCSession
/// and propagates wallet state changes to the Watch.
@MainActor
public final class WatchConnectivityService: NSObject, ObservableObject {

    public var onSessionReceived: ((BreathingSessionRecord) -> Void)?
    public var onSessionStarted: ((SessionStartedMessage) -> Void)?
    public var onSessionPhaseHint: ((SessionPhaseHintMessage) -> Void)?
    public var onCalibrationReceived: ((ResonanceFrequencyResult) -> Void)?
    public var onCalibrationFailed: ((CalibrationFailurePayload?) -> Void)?
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

    @discardableResult
    public func sendStartSession(
        bpm: Double,
        durationSeconds: Int,
        ratio: BreathRatio = .fourToSix,
        sessionId: String? = nil,
        companionAudioEnabled: Bool = false
    ) -> String {
        let id = sessionId ?? UUID().uuidString
        guard WCSession.default.isReachable else {
            DiagnosticLog.shared.record(
                source: "iOS",
                category: "watchConnectivity",
                level: .warning,
                message: "Start session not sent; watch unreachable",
                metadata: ["sessionId": id])
            return id
        }
        let cmd = StartSessionCommand(
            bpm: bpm,
            durationSeconds: durationSeconds,
            ratio: ratio.rawValue,
            sessionId: id,
            companionAudioEnabled: companionAudioEnabled ? true : nil
        )
        guard let message = try? makeWatchMessage(type: .startSession, payload: cmd) else { return id }
        WCSession.default.sendMessage(message, replyHandler: nil)
        DiagnosticLog.shared.record(
            source: "iOS",
            category: "watchConnectivity",
            message: "Sent start session to watch",
            metadata: [
                "sessionId": id,
                "bpm": String(format: "%.1f", bpm),
                "duration": String(durationSeconds),
                "companionAudio": String(companionAudioEnabled)
            ])
        return id
    }

    /// Sends a start-calibration command to the Watch. Returns false if Watch isn't reachable —
    /// caller should prompt the user to open the Watch app.
    @discardableResult
    public func sendStartCalibration(sampleDurationPerRate: TimeInterval? = nil) -> Bool {
        guard WCSession.default.isReachable else {
            DiagnosticLog.shared.record(
                source: "iOS",
                category: "watchConnectivity",
                level: .warning,
                message: "Start calibration not sent; watch unreachable")
            return false
        }
        if let sampleDurationPerRate {
            let command = StartCalibrationCommand(sampleDurationPerRate: sampleDurationPerRate)
            guard let message = try? makeWatchMessage(type: .startCalibration, payload: command) else {
                return false
            }
            WCSession.default.sendMessage(message, replyHandler: nil)
        } else {
            WCSession.default.sendMessage(makeWatchMessage(type: .startCalibration), replyHandler: nil)
        }
        DiagnosticLog.shared.record(
            source: "iOS",
            category: "watchConnectivity",
            message: "Sent start calibration to watch",
            metadata: ["rateSeconds": sampleDurationPerRate.map { String(format: "%.0f", $0) } ?? "default"])
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
        DiagnosticLog.shared.record(
            source: "iOS",
            category: "watchConnectivity",
            message: "Watch reachability changed",
            metadata: ["reachable": String(isWatchReachable)])
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
        guard let type = watchMessageType(from: message) else {
            logIgnoredWatchMessage(reason: "missing or unknown type", message: message)
            return
        }
        switch type {
        case .sessionComplete:
            guard let record = decodeSessionComplete(from: message) else { return }
            DiagnosticLog.shared.record(
                source: "iOS",
                category: "watchConnectivity",
                message: "Received watch session complete",
                metadata: [
                    "sessionId": record.id,
                    "source": record.source.rawValue,
                    "avgHRV": record.avgHRV.map { String(format: "%.1f", $0) } ?? "nil",
                    "coherence": record.coherenceScore.map { String(format: "%.3f", $0) } ?? "nil"
                ])
            Task { @MainActor [weak self] in self?.onSessionReceived?(record) }
        case .sessionStarted:
            guard let started = decodeSessionStarted(from: message) else { return }
            Task { @MainActor [weak self] in self?.onSessionStarted?(started) }
        case .sessionPhaseHint:
            guard let hint = decodeSessionPhaseHint(from: message) else { return }
            Task { @MainActor [weak self] in self?.onSessionPhaseHint?(hint) }
        case .calibrationResult:
            guard let result = try? decodeWatchPayload(ResonanceFrequencyResult.self, from: message) else {
                logIgnoredWatchMessage(reason: "calibrationResult decode failed", message: message)
                return
            }
            Task { @MainActor [weak self] in self?.onCalibrationReceived?(result) }
        case .calibrationFailed:
            let payload = try? decodeWatchPayload(CalibrationFailurePayload.self, from: message)
            Task { @MainActor [weak self] in self?.onCalibrationFailed?(payload) }
        case .diagnosticEvent:
            if let event = try? decodeWatchPayload(DiagnosticEvent.self, from: message) {
                DiagnosticLog.shared.append(event)
            }
        case .walletStateRequest:
            Task { @MainActor [weak self] in self?.onWalletStateRequested?() }
        default:
            break
        }
    }
}

// MARK: - Defensive decoding (never trap on malformed Watch payloads)

extension WatchConnectivityService {
    nonisolated fileprivate func decodeSessionComplete(
        from message: [String: Any]
    ) -> BreathingSessionRecord? {
        guard let record = try? decodeWatchPayload(BreathingSessionRecord.self, from: message) else {
            logIgnoredWatchMessage(reason: "sessionComplete decode failed", message: message)
            return nil
        }
        guard !record.id.isEmpty else {
            logIgnoredWatchMessage(reason: "sessionComplete missing id", message: message)
            return nil
        }
        return record
    }

    nonisolated fileprivate func decodeSessionStarted(
        from message: [String: Any]
    ) -> SessionStartedMessage? {
        guard let started = try? decodeWatchPayload(SessionStartedMessage.self, from: message) else {
            logIgnoredWatchMessage(reason: "sessionStarted decode failed", message: message)
            return nil
        }
        guard !started.sessionId.isEmpty, started.bpm > 0, started.durationSeconds > 0 else {
            logIgnoredWatchMessage(reason: "sessionStarted invalid fields", message: message)
            return nil
        }
        return started
    }

    nonisolated fileprivate func decodeSessionPhaseHint(
        from message: [String: Any]
    ) -> SessionPhaseHintMessage? {
        guard let hint = try? decodeWatchPayload(SessionPhaseHintMessage.self, from: message) else {
            logIgnoredWatchMessage(reason: "sessionPhaseHint decode failed", message: message)
            return nil
        }
        guard !hint.sessionId.isEmpty else {
            logIgnoredWatchMessage(reason: "sessionPhaseHint missing sessionId", message: message)
            return nil
        }
        return hint
    }

    nonisolated fileprivate func logIgnoredWatchMessage(
        reason: String,
        message: [String: Any]
    ) {
        #if DEBUG
        let type = message[WatchMessageKey.type.rawValue] as? String ?? "?"
        print("[WatchConnectivity] ignored \(type): \(reason)")
        #endif
    }
}
