import Foundation
import Combine
import WatchConnectivity
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

    private var currentRateIndex: Int = 0
    private var collectedSamples: [Double: [Double]] = [:]
    private var rateTimer: Timer?

    /// Set when the rate's sample window expires; deferred transition
    /// fires on the next inhale start so we never cut a breath in half.
    private var pendingRateTransition: Bool = false
    private var lastBreathPhase: BreathPhase?

    private var cancellables = Set<AnyCancellable>()

    private static let log = Logger(
        subsystem: "com.amach.AmachBreathe", category: "Calibration")

    // MARK: - Init

    public override init() {
        super.init()
        audioPacer = AudioPacer(timer: timer)
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

        // HealthKit workout is best-effort — without it we lose RR intervals
        // (so calibration can't produce a result), but the breath pacer must
        // still run. Kick HK off in a detached Task instead of awaiting:
        // on the watchOS simulator the missing entitlement causes
        // beginCollection(at:) to hang forever, which would block the pacer
        // start indefinitely.
        Task { [workoutManager] in
            try? await workoutManager.startWorkout()
        }
        await startNextRate()
    }

    public func cancel() async {
        rateTimer?.invalidate()
        rateTimer = nil
        timer.stop()
        cancellables.removeAll()
        pendingRateTransition = false
        lastBreathPhase = nil
        await workoutManager.stopWorkout()
        isRunning = false
        pacerState = .idle
        calibrationState = .idle
    }

    // MARK: - Per-rate steps

    private func startNextRate() async {
        let candidates = CalibrationEngine.candidateBPMs
        guard currentRateIndex < candidates.count else {
            await finalize()
            return
        }

        let bpm = candidates[currentRateIndex]
        hrvProcessor.reset()
        pendingRateTransition = false
        lastBreathPhase = nil

        // Start visual/haptic/audio pacer at this rate (warmup phase, no HK session phase change)
        timer.start(bpm: bpm, mainDurationSeconds: Int(sampleDurationPerRate),
                    ratio: .fourToSix)

        calibrationState = .running(rateIndex: currentRateIndex, bpm: bpm, elapsed: 0)
        Self.log.info("Rate \(self.currentRateIndex, privacy: .public) start: \(bpm, privacy: .public) BPM")

        // Subscribe to timer for elapsed display, pacer ring animation, and
        // detection of the next inhale start when a rate transition is pending.
        timer.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.pacerState = state
                if case .running(let idx, _, _) = self.calibrationState {
                    self.calibrationState = .running(
                        rateIndex: idx, bpm: bpm,
                        elapsed: state.sessionPhaseElapsed)
                }
                self.handleBreathPhaseForTransition(state, bpm: bpm)
            }
            .store(in: &cancellables)

        // Mark the rate window as expired; the next inhale start triggers
        // rateCompleted so the breath cycle is never cut mid-phase.
        rateTimer = Timer.scheduledTimer(
            withTimeInterval: sampleDurationPerRate, repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pendingRateTransition = true
                Self.log.info("Rate \(self.currentRateIndex, privacy: .public) (\(bpm, privacy: .public) BPM) window expired — awaiting next inhale")
            }
        }
    }

    /// Called from the timer.$state sink. When a rate transition is pending
    /// and we observe an exhale→inhale transition, run rateCompleted.
    private func handleBreathPhaseForTransition(_ state: PacerState, bpm: Double) {
        guard state.sessionPhase.isActive else { return }
        let prev = lastBreathPhase
        lastBreathPhase = state.breathPhase

        guard pendingRateTransition,
              prev == .exhale,
              state.breathPhase == .inhale else { return }

        pendingRateTransition = false
        Self.log.info("Inhale start at \(state.sessionPhaseElapsed, privacy: .public)s — closing rate \(self.currentRateIndex, privacy: .public) (\(bpm, privacy: .public) BPM)")
        Task { @MainActor [weak self] in await self?.rateCompleted(bpm: bpm) }
    }

    private func rateCompleted(bpm: Double) async {
        timer.stop()
        cancellables.removeAll()
        pendingRateTransition = false
        lastBreathPhase = nil

        // Collect the current window of RR intervals for this rate
        let window = hrvProcessor.currentWindow
        if !window.isEmpty {
            collectedSamples[bpm] = window
        }

        currentRateIndex += 1
        await startNextRate()
    }

    private func finalize() async {
        await workoutManager.stopWorkout()
        isRunning = false

        guard let result = engine.findResonance(samples: collectedSamples) else {
            calibrationState = .failed
            return
        }

        let record = CalibrationRecord(result: result)
        calibrationState = .complete(result: record)
        sendResultToPhone(result)
    }

    // MARK: - HRV collection

    private func handleRRInterval(_ rrMs: Double) {
        hrvProcessor.addRRInterval(rrMs)
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
}
