import Foundation

/// Pure, timer-free phase lifecycle for a resonance breathing session.
/// Call `tick(now:)` at any rate to advance state; transitions happen automatically.
/// Supports pause/resume with exact elapsed-time preservation.
///
/// All mutations are unsynchronised — callers own the locking or serial-queue guarantee.
public struct SessionPhaseController: Sendable {

    // MARK: - Config

    public struct Config: Sendable {
        public let mainDurationSeconds: Int
        public init(mainDurationSeconds: Int) {
            self.mainDurationSeconds = mainDurationSeconds
        }
    }

    // MARK: - Tick result

    public struct TickResult: Sendable {
        public let phase: SessionPhase
        public let phaseElapsed: TimeInterval
        public let phaseRemaining: TimeInterval?
        public let totalElapsed: TimeInterval
        /// Non-nil only on the tick where a phase transition occurred.
        public let transitionedTo: SessionPhase?

        public var isComplete: Bool {
            if case .complete = phase { return true }
            return false
        }
    }

    // MARK: - State

    private let phaseSequence: [SessionPhase]

    private var sessionStartDate: Date?
    private var phaseStartDate: Date?
    /// Elapsed within current phase accumulated before the most recent pause.
    private var accumulatedPhaseElapsed: TimeInterval = 0
    /// Date when current pause began (nil = running).
    private var pauseStartDate: Date?
    /// Total wall-clock time spent paused (used to correct totalElapsed).
    private var totalPauseDuration: TimeInterval = 0

    public private(set) var phaseIndex: Int = 0

    // MARK: - Accessors

    public var currentPhase: SessionPhase {
        guard phaseIndex < phaseSequence.count else { return .complete }
        return phaseSequence[phaseIndex]
    }

    public var isPaused: Bool { pauseStartDate != nil }
    public var isStarted: Bool { sessionStartDate != nil }

    // MARK: - Init

    public init(config: Config) {
        phaseSequence = [
            .baseline,
            .warmup,
            .main(durationSeconds: config.mainDurationSeconds),
            .recovery,
            .reflection
        ]
    }

    // MARK: - Control

    public mutating func start(at date: Date) {
        sessionStartDate = date
        phaseStartDate = date
        phaseIndex = 0
        accumulatedPhaseElapsed = 0
        pauseStartDate = nil
        totalPauseDuration = 0
    }

    /// Freeze elapsed time. Returns silently if already paused or not started.
    public mutating func pause(at date: Date) {
        guard !isPaused, let pStart = phaseStartDate else { return }
        accumulatedPhaseElapsed += date.timeIntervalSince(pStart)
        phaseStartDate = nil
        pauseStartDate = date
    }

    /// Resume from pause. Returns silently if not paused.
    public mutating func resume(at date: Date) {
        guard isPaused, let pauseStart = pauseStartDate else { return }
        totalPauseDuration += date.timeIntervalSince(pauseStart)
        pauseStartDate = nil
        phaseStartDate = date
    }

    // MARK: - Tick

    /// Advance state to `now`. May trigger phase transition.
    /// Safe to call while paused — returns frozen state in that case.
    @discardableResult
    public mutating func tick(now: Date) -> TickResult {
        guard let sessionStart = sessionStartDate else {
            return TickResult(
                phase: .idle, phaseElapsed: 0, phaseRemaining: nil,
                totalElapsed: 0, transitionedTo: nil
            )
        }

        // Total elapsed excludes all paused intervals (including current if paused).
        let pausedSoFar = totalPauseDuration
            + (pauseStartDate.map { now.timeIntervalSince($0) } ?? 0)
        let totalElapsed = max(0, now.timeIntervalSince(sessionStart) - pausedSoFar)

        // Phase elapsed — frozen if paused.
        var phaseElapsed: TimeInterval
        if isPaused {
            phaseElapsed = accumulatedPhaseElapsed
        } else {
            phaseElapsed = accumulatedPhaseElapsed
                + (phaseStartDate.map { now.timeIntervalSince($0) } ?? 0)
        }

        var transitioned: SessionPhase?

        // Auto-advance when target duration reached (only while running).
        if !isPaused, let target = currentPhase.targetDurationSeconds,
           phaseElapsed >= Double(target) {
            let overshoot = phaseElapsed - Double(target)
            phaseIndex += 1
            accumulatedPhaseElapsed = 0
            phaseStartDate = now.addingTimeInterval(-overshoot)
            phaseElapsed = overshoot

            if phaseIndex < phaseSequence.count {
                transitioned = phaseSequence[phaseIndex]
            } else {
                transitioned = .complete
                phaseStartDate = nil
            }
        }

        let phaseRemaining = currentPhase.targetDurationSeconds
            .map { max(0, Double($0) - phaseElapsed) }

        return TickResult(
            phase: currentPhase,
            phaseElapsed: phaseElapsed,
            phaseRemaining: phaseRemaining,
            totalElapsed: totalElapsed,
            transitionedTo: transitioned
        )
    }
}
