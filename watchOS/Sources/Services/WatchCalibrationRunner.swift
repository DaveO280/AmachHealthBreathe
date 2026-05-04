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
        case failed
    }

    @Published public private(set) var calibrationState: State = .idle
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var pacerState: PacerState = .idle

    // MARK: - Config

    public var sampleDurationPerRate: TimeInterval = 60   // seconds per candidate

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
        collectedSamples = [:]
        currentRateIndex = 0
        isRunning = true
        lastRingScale = nil

        // Re-arm AVAudioSession in case it was deactivated since init —
        // the AudioPacer is created at app launch, but the audio route can
        // be reclaimed (e.g. by another app) before the user gets to
        // calibration. Re-preparing makes the first thump audible.
        audioPacer.prepare()

        startExtendedRuntimeSession()

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

        // HealthKit workout is best-effort — without it we lose RR intervals
        // (so calibration can't produce a result), but the breath pacer must
        // still run. Kick HK off in a detached Task instead of awaiting:
        // on the watchOS simulator the missing entitlement causes
        // beginCollection(at:) to hang forever, which would block the pacer
        // start indefinitely.
        Task { [workoutManager] in
            try? await workoutManager.startWorkout()
        }
        // Diagnostic: workout session is what keeps the display awake on
        // device. If `isActive` stays false past startup, the screen will
        // sleep normally and we know the detached Task failed silently.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self else { return }
            Self.log.info("WORKOUT_ACTIVE_CHECK calibration active=\(self.workoutManager.isActive, privacy: .public)")
        }
        Self.log.info("Calibration start (rates: \(CalibrationEngine.candidateBPMs.map { "\($0)" }.joined(separator: ","), privacy: .public))")
        await startNextRate()
    }

    public func cancel() async {
        rateTimer?.invalidate()
        rateTimer = nil
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
        cancellables.removeAll()
        isRunning = false
        pacerState = .idle

        // Stop HK in a detached Task — same simulator-hang reason as start().
        Task { [workoutManager] in
            await workoutManager.stopWorkout()
        }
        invalidateExtendedRuntimeSession()

        guard let result = engine.findResonance(samples: collectedSamples) else {
            calibrationState = .failed
            Self.log.info("CALIBRATION_FAILED no resonance from \(self.collectedSamples.count, privacy: .public) rate samples")
            sendFailureToPhone()
            return
        }

        let record = CalibrationRecord(result: result)
        calibrationState = .complete(result: record)
        Self.log.info("CALIBRATION_COMPLETE bpm=\(result.resonanceBPM, privacy: .public)")
        sendResultToPhone(result)
    }

    // MARK: - HRV collection

    private func handleRRInterval(_ rrMs: Double) {
        hrvProcessor.addRRInterval(rrMs)
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

    // MARK: - WatchConnectivity

    private func sendResultToPhone(_ result: ResonanceFrequencyResult) {
        guard WCSession.isSupported() else { return }
        guard let message = try? makeWatchMessage(
            type: .calibrationResult, payload: result) else { return }
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil)
        } else {
            // iPhone not in foreground — deliver when it next becomes active
            session.transferUserInfo(message)
        }
    }

    /// Tell the phone calibration finished without producing a usable result so
    /// it can drop the awaiting-result state instead of waiting forever.
    private func sendFailureToPhone() {
        guard WCSession.isSupported() else { return }
        let message = makeWatchMessage(type: .calibrationFailed)
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil)
        } else {
            session.transferUserInfo(message)
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
    }
}
