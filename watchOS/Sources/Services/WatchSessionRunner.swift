import Foundation
import Combine
import WatchConnectivity
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

    private var bpm: Double = 5.5
    private var mainDurationSeconds: Int = 300
    private var sessionId: String = ""
    private var reflectionRating: Int?

    // Snapshot HRV at phase boundaries
    private var baselineHRV: Double = 0
    private var recoveryHRV: Double = 0

    // Coherence accumulation during main phase
    private var coherenceSamples: [Double] = []

    private var cancellables = Set<AnyCancellable>()

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

    public func startSession(bpm: Double, durationSeconds: Int) async throws {
        self.bpm = bpm
        self.mainDurationSeconds = durationSeconds
        self.sessionId = UUID().uuidString
        self.reflectionRating = nil
        self.baselineHRV = 0
        self.recoveryHRV = 0
        self.coherenceSamples = []
        hrvProcessor.reset()

        try await workoutManager.startWorkout()
        timer.start(bpm: bpm, mainDurationSeconds: durationSeconds)
        isRunning = true
    }

    public func stopSession() async {
        timer.stop()
        hapticPacer.stop()
        audioPacer.stop()
        await workoutManager.stopWorkout()
        isRunning = false
    }

    public func submitReflection(rating: Int) {
        reflectionRating = rating
        buildRecord()
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
        let prevPhase = phase
        phase = state.sessionPhase
        pacerState = state

        // Snapshot HRV at phase transitions
        if prevPhase != state.sessionPhase {
            switch state.sessionPhase {
            case .warmup:
                baselineHRV = hrvProcessor.rmssd ?? 0
            case .recovery:
                coherenceSamples = []  // reset — will collect during recovery too, unused
            case .reflection:
                recoveryHRV = hrvProcessor.rmssd ?? 0
                // Auto-finalize without rating if Watch doesn't receive one
            case .complete:
                if reflectionRating == nil { buildRecord() }
            default: break
            }
        }

        // Sample coherence during main phase
        if case .main = state.sessionPhase {
            let window = hrvProcessor.currentWindow
            if let score = coherenceCalc.coherenceScore(rrIntervals: window, targetBPM: bpm) {
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
        let avgCoherence = coherenceSamples.isEmpty
            ? 0.0
            : coherenceSamples.reduce(0, +) / Double(coherenceSamples.count)

        let record = BreathingSessionRecord(
            id: sessionId,
            timestamp: Date(),
            durationSeconds: mainDurationSeconds,
            bpm: bpm,
            ratio: "4:6",
            baselineHRV: baselineHRV,
            recoveryHRV: recoveryHRV,
            avgHRV: hrvProcessor.rmssd ?? 0,
            coherenceScore: avgCoherence,
            reflectionRating: reflectionRating
        )
        completedRecord = record
        Task { await sendRecordToPhone(record) }
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
        guard let session = wcSession, session.isReachable else { return }
        guard let message = try? makeWatchMessage(type: .sessionComplete, payload: record) else { return }
        session.sendMessage(message, replyHandler: nil)
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
            guard let cmd = try? decodeWatchPayload(StartSessionCommand.self, from: message) else { return }
            Task { @MainActor [weak self] in
                try? await self?.startSession(bpm: cmd.bpm, durationSeconds: cmd.durationSeconds)
            }
        case .cancelSession:
            Task { @MainActor [weak self] in await self?.stopSession() }
        default: break
        }
    }
}
