import Foundation
import Combine
import WatchConnectivity
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

    private var currentRateIndex: Int = 0
    private var collectedSamples: [Double: [Double]] = [:]
    private var rateTimer: Timer?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    public override init() {
        super.init()
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

        // Start visual/haptic/audio pacer at this rate (warmup phase, no HK session phase change)
        timer.start(bpm: bpm, mainDurationSeconds: Int(sampleDurationPerRate),
                    ratio: .fourToSix)

        calibrationState = .running(rateIndex: currentRateIndex, bpm: bpm, elapsed: 0)

        // Subscribe to timer for elapsed display and pacer ring animation
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
            }
            .store(in: &cancellables)

        // Schedule rate completion
        rateTimer = Timer.scheduledTimer(
            withTimeInterval: sampleDurationPerRate, repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.rateCompleted(bpm: bpm) }
        }
    }

    private func rateCompleted(bpm: Double) async {
        timer.stop()
        cancellables.removeAll()

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
