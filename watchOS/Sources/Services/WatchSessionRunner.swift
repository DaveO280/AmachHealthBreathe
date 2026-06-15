import Foundation
import Combine
import WatchConnectivity
import WatchKit
import WidgetKit
import os
import AmachBreatheShared

/// Orchestrates a complete breathing session on Apple Watch.
/// Owns MasterPhaseTimer, HRVProcessor, CoherenceCalculator, HKWorkoutSessionManager,
/// and all three pacers. Produces a BreathingSessionRecord on completion.
@MainActor
public final class WatchSessionRunner: NSObject, ObservableObject {

    // MARK: - Published state

    @Published public private(set) var phase: SessionPhase = .idle
    @Published public private(set) var pacerState: PacerState = .idle
    @Published public private(set) var currentCoherence: Double = 0
    @Published public private(set) var currentHRV: Double = 0
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var completedRecord: BreathingSessionRecord?

    // MARK: - Sub-services

    public let timer = MasterPhaseTimer()
    public private(set) var visualPacer: VisualPacer!
    private var hapticPacer: HapticPacer!
    private var audioPacer: AudioPacer!
    private let hrvProcessor = HRVProcessor()
    private let coherenceCalc = CoherenceCalculator()
    private let workoutManager = HKWorkoutSessionManager()
    private var wcSession: WCSession?

    // MARK: - Session config

    // Set by AmachBreatheWatchApp after both objects are created
    public weak var calibrationRunner: WatchCalibrationRunner?

    private var bpm: Double = 5.5
    private var selectedRatio: BreathRatio = .fourToSix
    private var mainDurationSeconds: Int = 300
    private var sessionId: String = ""
    private var reflectionRating: Int?

    private var baselineHRV: Double = 0
    private var recoveryHRV: Double = 0
    private var coherenceSamples: [Double] = []

    private var cancellables = Set<AnyCancellable>()

    /// Keeps the watch awake for the full session. HKWorkoutSession should
    /// theoretically do this, but we kick it off in a detached Task (to avoid a
    /// simulator hang) so on real hardware it may not start fast enough.
    /// WKExtendedRuntimeSession is the supported API for keeping the watch
    /// awake during guided activities like breathing sessions.
    private var extendedRuntimeSession: WKExtendedRuntimeSession?

    nonisolated private static let log = Logger(
        subsystem: "com.amach.AmachBreathe", category: "Session")

    // MARK: - Init

    public override init() {
        super.init()
        visualPacer = VisualPacer(timer: timer)
        hapticPacer = HapticPacer(timer: timer)
        audioPacer = AudioPacer(timer: timer)

        workoutManager.onRRInterval = { [weak self] rrMs in
            self?.handleRRInterval(rrMs)
        }

        subscribeToTimer()
        setupWCSession()
    }

    // MARK: - Public API

    public func requestHealthKitAuthorization() async throws {
        try await workoutManager.requestAuthorization()
    }

    public func startSession(
        bpm: Double,
        durationSeconds: Int,
        ratio: BreathRatio = .fourToSix,
        sessionId: String? = nil
    ) async throws {
        self.bpm = bpm
        self.selectedRatio = ratio
        self.mainDurationSeconds = durationSeconds
        self.sessionId = sessionId ?? UUID().uuidString
        self.reflectionRating = nil
        self.completedRecord = nil
        self.baselineHRV = 0
        self.recoveryHRV = 0
        updateComplicationState(inSession: true)
        self.coherenceSamples = []
        hrvProcessor.reset()
        recordDiagnostic(
            category: "session",
            message: "Watch session starting",
            metadata: [
                "sessionId": self.sessionId,
                "bpm": String(format: "%.1f", bpm),
                "duration": String(durationSeconds)
            ])

        // Re-arm AVAudioSession (see WatchCalibrationRunner.start for the
        // same rationale — pacer init at app launch can leave the audio
        // route stale by the time the user starts a session).
        audioPacer.prepare()

        // HealthKit workout is best-effort — without it we lose HRV/coherence
        // but the breathing pacer must still run. Kick HK off in a detached
        // Task rather than awaiting: on the watchOS simulator the missing
        // entitlement causes beginCollection(at:) to hang forever, which
        // would block the pacer start indefinitely.
        Task { [workoutManager] in
            try? await workoutManager.startWorkout()
        }
        startExtendedRuntimeSession()
        // Screen stays on via active HKWorkoutSession (.running state)
        timer.start(bpm: bpm, mainDurationSeconds: durationSeconds, ratio: ratio)
        isRunning = true
        isPaused = false
        sendSessionStartedToPhone()

        // Diagnostic: confirm the workout session actually started on device.
        // If `isActive` stays false past startup, the display will sleep
        // normally and we know the detached Task failed silently.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self else { return }
            Self.log.info("WORKOUT_ACTIVE_CHECK session active=\(self.workoutManager.isActive, privacy: .public)")
            self.recordDiagnostic(
                category: "healthKit",
                level: self.workoutManager.isActive ? .info : .warning,
                message: "Workout active check",
                metadata: ["active": String(self.workoutManager.isActive)])
        }
    }

    public func stopSession() async {
        if !sessionId.isEmpty { sendPhaseHintToPhone(.sessionEnded) }
        timer.stop()
        hapticPacer.stop()
        audioPacer.stop()
        phase = .idle
        pacerState = .idle
        isRunning = false
        isPaused = false
        updateComplicationState(inSession: false)
        invalidateExtendedRuntimeSession()

        await workoutManager.stopWorkout()
    }

    public func pause() {
        guard isRunning, !isPaused else { return }
        timer.pause()
        isPaused = true
    }

    public func resume() {
        guard isRunning, isPaused else { return }
        timer.resume()
        isPaused = false
    }

    /// Called from the reflection view when the user submits a star rating.
    public func submitReflection(rating: Int) {
        reflectionRating = rating
        buildRecord()
        phase = .complete
    }

    /// Called when the user taps Done on the completion screen.
    public func endSession() async {
        hapticPacer.stop()
        audioPacer.stop()
        timer.stop()
        isRunning = false
        isPaused = false
        phase = .idle
        pacerState = .idle
        updateComplicationState(inSession: false)
        invalidateExtendedRuntimeSession()
        await workoutManager.stopWorkout()
    }

    // MARK: - Phase observation

    private func subscribeToTimer() {
        timer.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.handleTimerState(state)
            }
            .store(in: &cancellables)
    }

    private func handleTimerState(_ state: PacerState) {
        pacerState = state
        let prevPhase = phase

        // Don't let the timer override .complete — submitReflection owns that transition.
        if case .complete = phase { return }

        phase = state.sessionPhase

        if prevPhase != state.sessionPhase {
            switch state.sessionPhase {
            case .warmup:
                baselineHRV = hrvProcessor.rmssd ?? 0
            case .main:
                sendPhaseHintToPhone(.mainStarted)
            case .recovery:
                break
            case .reflection:
                recoveryHRV = hrvProcessor.rmssd ?? 0
                sendPhaseHintToPhone(.sessionEnded)
            case .complete:
                if reflectionRating == nil { buildRecord() }
                phase = .complete
            default: break
            }
        }

        if case .main = state.sessionPhase {
            let window = hrvProcessor.currentWindow
            if let score = coherenceCalc.coherenceScore(
                rrIntervals: window, targetBPM: bpm) {
                coherenceSamples.append(score)
                currentCoherence = score
            }
        }
    }

    // MARK: - HRV

    private func handleRRInterval(_ rrMs: Double) {
        hrvProcessor.addRRInterval(rrMs)
        currentHRV = hrvProcessor.rmssd ?? 0
    }

    // MARK: - Build result

    private func buildRecord() {
        guard completedRecord == nil else { return }
        let avgCoherence = coherenceSamples.isEmpty
            ? 0.0
            : coherenceSamples.reduce(0, +) / Double(coherenceSamples.count)

        let record = BreathingSessionRecord(
            id: sessionId,
            timestamp: Date(),
            durationSeconds: mainDurationSeconds,
            bpm: bpm,
            ratio: selectedRatio.rawValue,
            baselineHRV: baselineHRV,
            recoveryHRV: recoveryHRV,
            avgHRV: hrvProcessor.rmssd ?? 0,
            coherenceScore: avgCoherence,
            reflectionRating: reflectionRating
        )
        completedRecord = record
        recordDiagnostic(
            category: "session",
            message: "Watch session built record",
            metadata: [
                "sessionId": sessionId,
                "avgHRV": record.avgHRV.map { String(format: "%.1f", $0) } ?? "nil",
                "coherence": record.coherenceScore.map { String(format: "%.3f", $0) } ?? "nil",
                "coherenceSamples": String(coherenceSamples.count)
            ])
        Task { await sendRecordToPhone(record) }
    }

    // MARK: - Extended runtime session

    private func startExtendedRuntimeSession() {
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start()
        extendedRuntimeSession = session
    }

    private func invalidateExtendedRuntimeSession() {
        extendedRuntimeSession?.invalidate()
        extendedRuntimeSession = nil
    }

    // MARK: - Complication state

    private func updateComplicationState(inSession: Bool) {
        UserDefaults.standard.set(inSession, forKey: ComplicationDisplayLogic.inSessionKey)
        UserDefaults.standard.set(true, forKey: ComplicationDisplayLogic.hasCalibrationKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - WatchConnectivity

    private func setupWCSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        wcSession = session
    }

    private func sendRecordToPhone(_ record: BreathingSessionRecord) async {
        guard WCSession.isSupported() else { return }
        guard let message = try? makeWatchMessage(
            type: .sessionComplete, payload: record) else { return }
        let session = wcSession ?? WCSession.default
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil)
            recordDiagnostic(
                category: "watchConnectivity",
                message: "Sent session complete to phone",
                metadata: ["sessionId": record.id, "delivery": "sendMessage"])
        } else {
            session.transferUserInfo(message)
            recordDiagnostic(
                category: "watchConnectivity",
                level: .warning,
                message: "Queued session complete for phone",
                metadata: ["sessionId": record.id, "delivery": "transferUserInfo"])
        }
    }

    private func sendSessionStartedToPhone() {
        guard WCSession.isSupported() else { return }
        let payload = SessionStartedMessage(
            sessionId: sessionId,
            bpm: bpm,
            durationSeconds: mainDurationSeconds,
            ratio: selectedRatio.rawValue
        )
        guard let message = try? makeWatchMessage(type: .sessionStarted, payload: payload) else { return }
        let session = wcSession ?? WCSession.default
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil)
            recordDiagnostic(
                category: "watchConnectivity",
                message: "Sent session started to phone",
                metadata: ["sessionId": sessionId, "delivery": "sendMessage"])
        } else {
            session.transferUserInfo(message)
            recordDiagnostic(
                category: "watchConnectivity",
                level: .warning,
                message: "Queued session started for phone",
                metadata: ["sessionId": sessionId, "delivery": "transferUserInfo"])
        }
    }

    private func sendPhaseHintToPhone(_ phase: CompanionPhaseHint) {
        guard WCSession.isSupported(), !sessionId.isEmpty else { return }
        let payload = SessionPhaseHintMessage(sessionId: sessionId, phase: phase)
        guard let message = try? makeWatchMessage(type: .sessionPhaseHint, payload: payload) else { return }
        let session = wcSession ?? WCSession.default
        guard session.isReachable else { return }
        session.sendMessage(message, replyHandler: nil)
    }

    private func recordDiagnostic(
        category: String,
        level: DiagnosticLevel = .info,
        message: String,
        metadata: [String: String] = [:]
    ) {
        let event = DiagnosticEvent(
            source: "watchOS",
            category: category,
            level: level,
            message: message,
            metadata: metadata
        )
        DiagnosticLog.shared.append(event)
        guard WCSession.isSupported() else { return }
        let session = wcSession ?? WCSession.default
        guard let payload = try? makeWatchMessage(type: .diagnosticEvent, payload: event) else { return }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil)
        } else {
            session.transferUserInfo(payload)
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionRunner: WCSessionDelegate {
    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) { }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        guard let type = watchMessageType(from: message) else { return }
        switch type {
        case .startSession:
            guard let cmd = try? decodeWatchPayload(
                StartSessionCommand.self, from: message) else { return }
            Task { @MainActor [weak self] in
                let ratio = cmd.ratio.flatMap(BreathRatio.init(rawValue:)) ?? .fourToSix
                try? await self?.startSession(
                    bpm: cmd.bpm,
                    durationSeconds: cmd.durationSeconds,
                    ratio: ratio,
                    sessionId: cmd.sessionId)
            }
        case .startCalibration:
            let cmd = try? decodeWatchPayload(
                StartCalibrationCommand.self, from: message)
            Task { @MainActor [weak self] in
                let duration = cmd?.sampleDurationPerRate
                    ?? WatchCalibrationRunner.defaultRateDuration
                self?.calibrationRunner?.sampleDurationPerRate = duration
                self?.recordDiagnostic(
                    category: "calibration",
                    message: "Received start calibration",
                    metadata: ["rateSeconds": String(format: "%.0f", duration)])
                await self?.calibrationRunner?.start()
            }
        case .cancelSession:
            Task { @MainActor [weak self] in
                await self?.stopSession()
                await self?.calibrationRunner?.cancel()
            }
        case .walletState:
            guard let msg = try? decodeWatchPayload(
                WalletStateMessage.self, from: message) else { return }
            Task { @MainActor in
                WatchWalletStore.shared.applyState(
                    isConnected: msg.isConnected, walletAddress: msg.walletAddress)
            }
        default: break
        }
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let connected = applicationContext["walletConnected"] as? Bool ?? false
        let address   = applicationContext["walletAddress"] as? String
        Task { @MainActor in
            WatchWalletStore.shared.applyState(isConnected: connected, walletAddress: address)
        }
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension WatchSessionRunner: WKExtendedRuntimeSessionDelegate {

    nonisolated public func extendedRuntimeSessionDidStart(
        _ extendedRuntimeSession: WKExtendedRuntimeSession
    ) {
        Self.log.info("EXTENDED_RUNTIME_STARTED session")
    }

    nonisolated public func extendedRuntimeSessionWillExpire(
        _ extendedRuntimeSession: WKExtendedRuntimeSession
    ) {
        Self.log.info("EXTENDED_RUNTIME_WILL_EXPIRE session")
    }

    nonisolated public func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        if let error {
            Self.log.error("EXTENDED_RUNTIME_INVALIDATED session reason=\(reason.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        } else {
            Self.log.info("EXTENDED_RUNTIME_INVALIDATED session reason=\(reason.rawValue, privacy: .public)")
        }
    }
}
