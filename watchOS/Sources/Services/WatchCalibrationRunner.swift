import Foundation
import Combine
import WatchConnectivity
import WatchKit
import os
import AmachBreatheShared

/// Runs the 6-rate calibration protocol on Apple Watch.
/// For each candidate BPM: starts MasterPhaseTimer at that rate for `sampleDuration` seconds,
/// collects RR intervals via HKWorkoutSessionManager, then evaluates with CalibrationEngine.
/// Sends the result to iPhone via WCSession.
@MainActor
public final class WatchCalibrationRunner: NSObject, ObservableObject {

    // MARK: - Public state

    public enum State {
        case idle
        case running(rateIndex: Int, bpm: Double, elapsed: TimeInterval)
        case complete(result: CalibrationRecord)
        case failed(payload: CalibrationFailurePayload)
    }

    @Published public private(set) var calibrationState: State = .idle
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var pacerState: PacerState = .idle

    // MARK: - Config

    /// Per-rate sample window. DEBUG cuts this to 10s so a full 6-rate
    /// calibration completes in ~1 minute instead of 6 — for fast simulator iteration
    /// during development. Compile-time (not runtime) so release builds
    /// always use the real 60s window.
    #if DEBUG
    public static let defaultRateDuration: TimeInterval = 10
    #else
    public static let defaultRateDuration: TimeInterval = 60
    #endif

    public var sampleDurationPerRate: TimeInterval = WatchCalibrationRunner.defaultRateDuration

    // MARK: - Private

    private let engine = CalibrationEngine()
    private let workoutManager = HKWorkoutSessionManager()
    private let timer = MasterPhaseTimer()
    private let hrvProcessor = HRVProcessor(windowDuration: 90)
    private var audioPacer: AudioPacer!
    private var hapticPacer: HapticPacer!

    private var currentRateIndex: Int = 0
    private var currentRateBPM: Double = 0
    private var collectedSamples: [Double: [Double]] = [:]
    private var rateTimer: Timer?
    private var wakeHealthTimer: Timer?

    /// Set when the rate's sample window expires; deferred transition
    /// fires on the next inhale start so we never cut a breath in half.
    private var pendingRateTransition: Bool = false
    private var lastBreathPhase: BreathPhase?

    /// Last ringScale we forwarded to the UI — used to detect discontinuities
    /// for diagnostic logging. Reset on each rate boundary so a legitimate
    /// 0.6→0.6 handoff is not flagged.
    private var lastRingScale: Double?

    private var cancellables = Set<AnyCancellable>()

    /// Keeps the watch awake for the full calibration. HKWorkoutSession should
    /// theoretically do this, but we kick the workout off in a detached Task
    /// (to avoid a simulator hang) so it may not start fast enough on real
    /// hardware. WKExtendedRuntimeSession is the supported API for keeping the
    /// watch awake during non-workout flows like guided breathing.
    private var extendedRuntimeSession: WKExtendedRuntimeSession?

    nonisolated private static let log = Logger(
        subsystem: "com.amach.AmachBreathe", category: "Calibration")

    // MARK: - Init

    public override init() {
        super.init()
        audioPacer = AudioPacer(timer: timer)
        hapticPacer = HapticPacer(timer: timer)
        workoutManager.onRRInterval = { [weak self] rrMs in
            self?.handleRRInterval(rrMs)
        }
    }

    // MARK: - Public API

    public func requestAuthorization() async throws {
        try await workoutManager.requestAuthorization()
    }

    public func start() async {
        guard case .idle = calibrationState else { return }
        invalidateExtendedRuntimeSession()
        collectedSamples = [:]
        currentRateIndex = 0
        isRunning = true
        lastRingScale = nil
        recordDiagnostic(
            category: "calibration",
            message: "Calibration starting",
            metadata: ["rateSeconds": String(format: "%.0f", sampleDurationPerRate)])

        // Screen stays on via active HKWorkoutSession (.running state)

        // Re-arm AVAudioSession in case it was deactivated since init —
        // the AudioPacer is created at app launch, but the audio route can
        // be reclaimed (e.g. by another app) before the user gets to
        // calibration. Re-preparing makes the first thump audible.
        audioPacer.prepare()

        startExtendedRuntimeSession()
        logCalibrationRuntimeMode()

        // Single persistent subscription across all 6 rates. Holding one sink
        // for the whole calibration prevents the brief `.idle` frame between
        // `timer.stop()` and `timer.start()` from popping `pacerState.ringScale`
        // back to 1.0 — that pop was the visible "expand and snap" glitch at
        // rate boundaries.
        timer.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.handleTimerState(state)
            }
            .store(in: &cancellables)

        // Bring up the HealthKit workout BEFORE starting rate 0. On real
        // Apple Watch the workout takes 1-3s to enter `running` and the first
        // HR sample arrives ~5-15s after beginCollection — fire-and-forget
        // means rate 0's 60s window can elapse with zero samples, so
        // findResonance returns nil and the user sees "Couldn't measure
        // resonance".
        //
        // Simulator carve-out: beginCollection(at:) hangs forever there
        // because the entitlement is missing. Awaiting would freeze
        // calibration at startup, so keep the historical fire-and-forget
        // behaviour so the pacer/test loop still run.
        #if targetEnvironment(simulator)
        Task { [workoutManager] in
            try? await workoutManager.requestAuthorization()
            try? await workoutManager.startWorkout()
        }
        #else
        do {
            try await workoutManager.requestAuthorization()
            try await workoutManager.startWorkout()
            Self.log.info("HK_READY active=\(self.workoutManager.isActive, privacy: .public)")
            recordDiagnostic(
                category: "healthKit",
                message: "Calibration HealthKit ready",
                metadata: ["active": String(workoutManager.isActive)])
        } catch {
            Self.log.error("HK_STARTUP_FAILED \(error.localizedDescription, privacy: .public) — continuing without HK")
            recordDiagnostic(
                category: "healthKit",
                level: .error,
                message: "Calibration HealthKit startup failed",
                metadata: ["error": error.localizedDescription])
        }
        // cancel() may have run on MainActor while we were awaiting HK
        // startup (user tapped the close button). Bail before we re-arm
        // calibrationState in startNextRate.
        guard isRunning else {
            Self.log.info("HK_STARTUP cancelled mid-await")
            return
        }
        #endif

        // Diagnostic: confirms HK is actually streaming samples a few seconds
        // into rate 0. If `isActive` is true but `sampleCount` is still 0
        // here, the workout started but no HR is reaching us — investigate
        // the data source / anchor query path.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self else { return }
            Self.log.info("WORKOUT_ACTIVE_CHECK calibration active=\(self.workoutManager.isActive, privacy: .public) samples=\(self.workoutManager.sampleCount, privacy: .public)")
            self.recordDiagnostic(
                category: "healthKit",
                level: self.workoutManager.isActive ? .info : .warning,
                message: "Calibration workout active check",
                metadata: [
                    "active": String(self.workoutManager.isActive),
                    "samples": String(self.workoutManager.sampleCount),
                    "latestHR": String(format: "%.0f", self.workoutManager.latestHeartRate)
                ])
            self.ensureWakeSessionsHealthy()
        }
        Self.log.info("Calibration start (rates: \(CalibrationEngine.candidateBPMs.map { "\($0)" }.joined(separator: ","), privacy: .public))")
        startWakeHealthTimer()
        await startNextRate()
    }

    public func cancel() async {
        rateTimer?.invalidate()
        rateTimer = nil
        wakeHealthTimer?.invalidate()
        wakeHealthTimer = nil
        timer.stop()
        cancellables.removeAll()
        pendingRateTransition = false
        lastBreathPhase = nil
        lastRingScale = nil
        // Stop HK in a detached Task — endCollection/finishWorkout can hang on
        // the simulator (same reason startWorkout() is detached above).
        Task { [workoutManager] in
            await workoutManager.stopWorkout()
        }
        invalidateExtendedRuntimeSession()
        isRunning = false
        pacerState = .idle
        calibrationState = .idle
        Self.log.info("Calibration canceled")
    }

    // MARK: - Per-rate steps

    private func startNextRate() async {
        let candidates = CalibrationEngine.candidateBPMs
        guard currentRateIndex < candidates.count else {
            await finalize()
            return
        }

        let bpm = candidates[currentRateIndex]
        currentRateBPM = bpm
        hrvProcessor.reset()
        pendingRateTransition = false
        lastBreathPhase = nil
        // Allow continuity from end-of-rate-N's inhale start (~0.6) to
        // start-of-rate-N+1's inhale (~0.6). Don't reset lastRingScale to nil
        // BEFORE starting; reset it AFTER one frame so the discontinuity check
        // doesn't fire on the boundary itself.
        lastRingScale = nil

        // Start visual/haptic/audio pacer at this rate (warmup phase, no HK session phase change)
        timer.start(bpm: bpm, mainDurationSeconds: Int(sampleDurationPerRate),
                    ratio: .fourToSix)

        calibrationState = .running(rateIndex: currentRateIndex, bpm: bpm, elapsed: 0)
        Self.log.info("RATE_START idx=\(self.currentRateIndex, privacy: .public) bpm=\(bpm, privacy: .public)")

        // Mark the rate window as expired; the next inhale start triggers
        // rateCompleted so the breath cycle is never cut mid-phase.
        rateTimer = Timer.scheduledTimer(
            withTimeInterval: sampleDurationPerRate, repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pendingRateTransition = true
                Self.log.info("RATE_WINDOW_EXPIRED idx=\(self.currentRateIndex, privacy: .public) bpm=\(bpm, privacy: .public) — awaiting next inhale")
            }
        }
    }

    /// Single sink for `timer.$state`. Filters out the brief `.idle` state
    /// emitted between rates so `pacerState` (and therefore the ring scale)
    /// stays continuous, and drives both the rate-transition and elapsed-time
    /// updates.
    private func handleTimerState(_ state: PacerState) {
        // Suppress `.idle` (between rates / on stop). Keep the last active
        // PacerState so the BreathingCoachView ring doesn't pop to 1.0.
        guard state.sessionPhase.isActive else { return }

        // Discontinuity diagnostic: log a warning if the ring jumps more than
        // 0.3 between consecutive frames (a legitimate 60 Hz tick should move
        // by < 0.05 at any of our breath rates).
        if let prev = lastRingScale,
           abs(state.ringScale - prev) > 0.3 {
            Self.log.error("RING_JUMP idx=\(self.currentRateIndex, privacy: .public) bpm=\(self.currentRateBPM, privacy: .public) prev=\(prev, privacy: .public) curr=\(state.ringScale, privacy: .public) breath=\(state.breathPhase.rawValue, privacy: .public)")
        }
        lastRingScale = state.ringScale

        pacerState = state

        if case .running(let idx, let bpm, _) = calibrationState {
            calibrationState = .running(
                rateIndex: idx, bpm: bpm,
                elapsed: state.sessionPhaseElapsed)
        }

        handleBreathPhaseForTransition(state)
    }

    /// When a rate transition is pending and we observe an exhale→inhale
    /// boundary, run rateCompleted.
    private func handleBreathPhaseForTransition(_ state: PacerState) {
        let prev = lastBreathPhase
        lastBreathPhase = state.breathPhase

        guard pendingRateTransition,
              prev == .exhale,
              state.breathPhase == .inhale else { return }

        pendingRateTransition = false
        let bpm = currentRateBPM
        Self.log.info("INHALE_BOUNDARY idx=\(self.currentRateIndex, privacy: .public) bpm=\(bpm, privacy: .public) elapsed=\(state.sessionPhaseElapsed, privacy: .public) ring=\(state.ringScale, privacy: .public) — closing rate")
        Task { @MainActor [weak self] in await self?.rateCompleted(bpm: bpm) }
    }

    private func rateCompleted(bpm: Double) async {
        // Hold onto the persistent subscription across the timer.stop/start
        // handoff — we deliberately DO NOT removeAll() here. The single sink's
        // `isActive` filter swallows the brief `.idle` state that timer.stop
        // publishes, keeping ringScale continuous into the next rate.
        timer.stop()
        rateTimer?.invalidate()
        rateTimer = nil
        pendingRateTransition = false
        lastBreathPhase = nil

        // Collect the current window of RR intervals for this rate
        let window = hrvProcessor.currentWindow
        if !window.isEmpty {
            collectedSamples[bpm] = window
        }
        Self.log.info("RATE_DONE idx=\(self.currentRateIndex, privacy: .public) bpm=\(bpm, privacy: .public) samples=\(window.count, privacy: .public)")
        recordDiagnostic(
            category: "calibration",
            level: window.isEmpty ? .warning : .info,
            message: "Calibration rate completed",
            metadata: [
                "index": String(currentRateIndex),
                "bpm": String(format: "%.1f", bpm),
                "rrSamples": String(window.count),
                "hkSamples": String(workoutManager.sampleCount)
            ])

        currentRateIndex += 1
        await startNextRate()
    }

    private func finalize() async {
        // Flip isRunning FIRST so the SessionView immediately swaps out of
        // CalibrationActiveView. On the simulator HKLiveWorkoutBuilder's
        // endCollection / finishWorkout can hang indefinitely; awaiting them
        // before flipping isRunning was the post-calibration freeze.
        rateTimer?.invalidate()
        rateTimer = nil
        wakeHealthTimer?.invalidate()
        wakeHealthTimer = nil
        cancellables.removeAll()
        isRunning = false
        pacerState = .idle

        // Stop HK in a detached Task — same simulator-hang reason as start().
        Task { [workoutManager] in
            await workoutManager.stopWorkout()
        }
        invalidateExtendedRuntimeSession()

        let totalSamples = workoutManager.sampleCount
        let perRate = collectedSamples.mapValues(\.count)
        let perRateLog = perRate.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",")
        let evaluation = engine.evaluate(samples: collectedSamples)
        let accepted = evaluation.acceptedRates.sorted()
        guard let result = engine.findResonance(samples: collectedSamples) else {
            let reason: CalibrationFailureReason = accepted.isEmpty ? .insufficientSamples : .noResonanceSignal
            let skippedLog = evaluation.skippedRates
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: ",")
            Self.log.error("CALIBRATION_FAILED reason=\(reason.rawValue, privacy: .public) accepted=\(accepted.count, privacy: .public) hkSamples=\(totalSamples, privacy: .public) perRate=[\(perRateLog, privacy: .public)] skipped=[\(skippedLog, privacy: .public)]")
            recordDiagnostic(
                category: "calibration",
                level: .error,
                message: "Calibration failed",
                metadata: [
                    "reason": reason.rawValue,
                    "acceptedRates": String(accepted.count),
                    "hkSamples": String(totalSamples),
                    "perRate": perRateLog,
                    "skipped": skippedLog,
                    "workoutActive": String(workoutManager.isActive)
                ])
            let payload = CalibrationFailurePayload(
                reason: reason,
                hkSampleCount: totalSamples,
                acceptedRateCount: accepted.count,
                totalRateCount: CalibrationEngine.candidateBPMs.count,
                perRateSampleCounts: perRate,
                workoutWasActive: workoutManager.isActive,
                latestHeartRate: workoutManager.latestHeartRate
            )
            calibrationState = .failed(payload: payload)
            sendFailureToPhone(payload)
            return
        }
        Self.log.info("CALIBRATION_PIPELINE hkSamples=\(totalSamples, privacy: .public) accepted=\(accepted.count, privacy: .public) acceptedRates=\(accepted.map { String($0) }.joined(separator: ","), privacy: .public) perRate=[\(perRateLog, privacy: .public)]")

        let record = CalibrationRecord(result: result)
        calibrationState = .complete(result: record)
        Self.log.info("CALIBRATION_COMPLETE bpm=\(result.resonanceBPM, privacy: .public)")
        recordDiagnostic(
            category: "calibration",
            message: "Calibration complete",
            metadata: [
                "resonanceBPM": String(format: "%.1f", result.resonanceBPM),
                "acceptedRates": String(accepted.count),
                "hkSamples": String(totalSamples),
                "perRate": perRateLog
            ])
        sendResultToPhone(result)
    }

    // MARK: - HRV collection

    private func handleRRInterval(_ rrMs: Double) {
        hrvProcessor.addRRInterval(rrMs)
    }

    // MARK: - Extended runtime session

    private func startExtendedRuntimeSession() {
        guard extendedRuntimeSession == nil else { return }
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start()
        extendedRuntimeSession = session
    }

    private func invalidateExtendedRuntimeSession() {
        extendedRuntimeSession?.invalidate()
        extendedRuntimeSession = nil
    }

    // MARK: - WatchConnectivity

    private func sendResultToPhone(_ result: ResonanceFrequencyResult) {
        guard WCSession.isSupported() else { return }
        guard let message = try? makeWatchMessage(
            type: .calibrationResult, payload: result) else { return }
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil)
            recordDiagnostic(
                category: "watchConnectivity",
                message: "Sent calibration result to phone",
                metadata: ["delivery": "sendMessage", "bpm": String(format: "%.1f", result.resonanceBPM)])
        } else {
            // iPhone not in foreground — deliver when it next becomes active
            session.transferUserInfo(message)
            recordDiagnostic(
                category: "watchConnectivity",
                level: .warning,
                message: "Queued calibration result for phone",
                metadata: ["delivery": "transferUserInfo", "bpm": String(format: "%.1f", result.resonanceBPM)])
        }
    }

    /// Tell the phone calibration finished without producing a usable result so
    /// it can drop the awaiting-result state instead of waiting forever.
    private func sendFailureToPhone(_ payload: CalibrationFailurePayload) {
        guard WCSession.isSupported() else { return }
        guard let message = try? makeWatchMessage(type: .calibrationFailed, payload: payload) else { return }
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil)
            recordDiagnostic(
                category: "watchConnectivity",
                message: "Sent calibration failure to phone",
                metadata: ["delivery": "sendMessage", "reason": payload.reason.rawValue])
        } else {
            session.transferUserInfo(message)
            recordDiagnostic(
                category: "watchConnectivity",
                level: .warning,
                message: "Queued calibration failure for phone",
                metadata: ["delivery": "transferUserInfo", "reason": payload.reason.rawValue])
        }
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
        let session = WCSession.default
        guard let payload = try? makeWatchMessage(type: .diagnosticEvent, payload: event) else { return }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil)
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func logCalibrationRuntimeMode() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["CALIBRATION_TEST_LOOPS"] != nil {
            Self.log.info("CALIBRATION_RUNTIME test-loop rateSec=\(self.sampleDurationPerRate, privacy: .public)")
        } else {
            Self.log.info("CALIBRATION_RUNTIME debug-default rateSec=\(self.sampleDurationPerRate, privacy: .public)")
        }
        #else
        Self.log.info("CALIBRATION_RUNTIME release-default rateSec=\(self.sampleDurationPerRate, privacy: .public)")
        #endif
    }

    private func startWakeHealthTimer() {
        wakeHealthTimer?.invalidate()
        wakeHealthTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.ensureWakeSessionsHealthy()
            }
        }
    }

    private func ensureWakeSessionsHealthy() {
        guard isRunning else { return }
        if extendedRuntimeSession == nil {
            Self.log.info("WAKE_RECOVERY restarting extended runtime")
            startExtendedRuntimeSession()
        }
        guard !workoutManager.isActive else { return }
        Self.log.info("WAKE_RECOVERY restarting workout session")
        Task { [workoutManager] in
            try? await workoutManager.requestAuthorization()
            try? await workoutManager.startWorkout()
        }
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension WatchCalibrationRunner: WKExtendedRuntimeSessionDelegate {

    nonisolated public func extendedRuntimeSessionDidStart(
        _ extendedRuntimeSession: WKExtendedRuntimeSession
    ) {
        Self.log.info("EXTENDED_RUNTIME_STARTED calibration")
    }

    nonisolated public func extendedRuntimeSessionWillExpire(
        _ extendedRuntimeSession: WKExtendedRuntimeSession
    ) {
        Self.log.info("EXTENDED_RUNTIME_WILL_EXPIRE calibration")
    }

    nonisolated public func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        if let error {
            Self.log.error("EXTENDED_RUNTIME_INVALIDATED calibration reason=\(reason.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        } else {
            Self.log.info("EXTENDED_RUNTIME_INVALIDATED calibration reason=\(reason.rawValue, privacy: .public)")
        }
        Task { @MainActor [weak self] in
            guard let self, self.isRunning else { return }
            self.extendedRuntimeSession = nil
            self.startExtendedRuntimeSession()
        }
    }
}
