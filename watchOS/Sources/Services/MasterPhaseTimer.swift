import Foundation
import Combine
import AmachBreatheShared

/// Drives the entire session at 60 Hz. All pacers subscribe to `statePublisher`.
/// Phase transitions are automatic based on wall-clock elapsed time.
@MainActor
public final class MasterPhaseTimer: ObservableObject {

    // MARK: - Public state

    @Published public private(set) var state: PacerState = .idle
    @Published public private(set) var isRunning: Bool = false

    // MARK: - Config

    public var bpm: Double = 5.5 {
        didSet { recomputeBreathPeriod() }
    }
    public var mainDurationSeconds: Int = 300  // 5 / 10 / 15 min

    // MARK: - Private

    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.amach.breathe.masterTimer", qos: .userInteractive)

    private var sessionStartDate: Date?
    private var phaseStartDate: Date?
    private var currentPhase: SessionPhase = .idle
    private var phaseSequence: [SessionPhase] = []
    private var phaseIndex: Int = 0

    // Breath cycle derived from bpm
    private var breathPeriod: TimeInterval = 60.0 / 5.5     // total cycle seconds
    // Ratio: 40% inhale / 60% exhale (resonance breathing default)
    private let inhaleRatio: Double = 0.4
    private var inhaleDuration: TimeInterval = 0
    private var exhaleDuration: TimeInterval = 0

    private let tickInterval: TimeInterval = 1.0 / 60.0

    public init() {
        recomputeBreathPeriod()
    }

    // MARK: - Control

    public func start(bpm: Double, mainDurationSeconds: Int) {
        self.bpm = bpm
        self.mainDurationSeconds = mainDurationSeconds

        phaseSequence = [
            .baseline,
            .warmup,
            .main(durationSeconds: mainDurationSeconds),
            .recovery,
            .reflection
        ]
        phaseIndex = 0

        let now = Date()
        sessionStartDate = now
        phaseStartDate = now
        currentPhase = phaseSequence[0]
        isRunning = true

        scheduleTimer()
    }

    public func stop() {
        cancelTimer()
        currentPhase = .idle
        state = .idle
        isRunning = false
    }

    public func advanceToReflection() {
        currentPhase = .reflection
        phaseStartDate = Date()
    }

    // MARK: - Timer

    private func scheduleTimer() {
        let src = DispatchSource.makeTimerSource(queue: timerQueue)
        src.schedule(deadline: .now(), repeating: tickInterval, leeway: .microseconds(500))
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let snapshot = self.buildSnapshot()
            Task { @MainActor [weak self] in
                self?.state = snapshot
            }
        }
        src.resume()
        timer = src
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Snapshot (called on timerQueue)

    private func buildSnapshot() -> PacerState {
        let now = Date()
        let totalElapsed = sessionStartDate.map { now.timeIntervalSince($0) } ?? 0
        var phaseElapsed = phaseStartDate.map { now.timeIntervalSince($0) } ?? 0

        // Auto-advance through phases
        if let target = currentPhase.targetDurationSeconds, phaseElapsed >= Double(target) {
            advancePhase(now: now)
            phaseElapsed = 0
        }

        let phaseRemaining: TimeInterval? = currentPhase.targetDurationSeconds.map {
            max(0, Double($0) - phaseElapsed)
        }

        // Breath cycle position
        let cyclePos = phaseElapsed.truncatingRemainder(dividingBy: breathPeriod)
        let (breathPhase, breathProgress) = breathPhaseAndProgress(cyclePos: cyclePos)

        // Ring scale: sinusoidal 0.6 → 1.4 over full breath cycle
        let ringScale = ringScaleFor(cyclePos: cyclePos)

        return PacerState(
            sessionPhase: currentPhase,
            breathPhase: breathPhase,
            breathProgress: breathProgress,
            ringScale: ringScale,
            totalElapsed: totalElapsed,
            sessionPhaseElapsed: phaseElapsed,
            sessionPhaseRemaining: phaseRemaining
        )
    }

    private func advancePhase(now: Date) {
        phaseIndex += 1
        if phaseIndex < phaseSequence.count {
            currentPhase = phaseSequence[phaseIndex]
        } else {
            currentPhase = .complete
            cancelTimer()
        }
        phaseStartDate = now
    }

    // MARK: - Breath math

    private func recomputeBreathPeriod() {
        breathPeriod = 60.0 / max(bpm, 0.1)
        inhaleDuration = breathPeriod * inhaleRatio
        exhaleDuration = breathPeriod * (1 - inhaleRatio)
    }

    private func breathPhaseAndProgress(cyclePos: Double) -> (BreathPhase, Double) {
        if cyclePos < inhaleDuration {
            return (.inhale, cyclePos / inhaleDuration)
        } else {
            let exhalePos = cyclePos - inhaleDuration
            return (.exhale, exhalePos / exhaleDuration)
        }
    }

    /// Sinusoidal ring scale: 1.0 at cycle midpoint, 0.6 at start, 1.4 at inhale peak.
    private func ringScaleFor(cyclePos: Double) -> Double {
        // One full sine wave over the breath period: peak at inhale top, trough at exhale end
        let phase = (cyclePos / breathPeriod) * 2.0 * Double.pi - Double.pi / 2.0
        let sine = sin(phase)  // -1 at start, +1 at 25% (end of inhale)
        return 1.0 + 0.4 * sine   // 0.6 … 1.4
    }
}
