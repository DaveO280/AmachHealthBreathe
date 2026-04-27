import Foundation
import Combine
import AmachBreatheShared

/// Drives the session at 60 Hz. Wraps SessionPhaseController (pause/resume, phase lifecycle)
/// and adds breath-cycle math (ratio, ring scale) to produce a PacerState each tick.
/// All mutations are on MainActor; the DispatchSourceTimer fires → posts to main actor.
@MainActor
public final class MasterPhaseTimer: ObservableObject {

    // MARK: - Published state

    @Published public private(set) var state: PacerState = .idle
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isPaused: Bool = false

    // MARK: - Config

    public var bpm: Double = 5.5 {
        didSet { recomputeBreathPeriod() }
    }
    public var mainDurationSeconds: Int = 300
    public var breathRatio: BreathRatio = .fourToSix {
        didSet { recomputeBreathPeriod() }
    }

    // MARK: - Private

    private var controller: SessionPhaseController?
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(
        label: "com.amach.breathe.masterTimer", qos: .userInteractive)

    private var breathPeriod: TimeInterval = 60.0 / 5.5
    private var inhaleDuration: TimeInterval = 0
    private var exhaleDuration: TimeInterval = 0
    private let tickInterval: TimeInterval = 1.0 / 60.0

    public init() { recomputeBreathPeriod() }

    // MARK: - Control

    public func start(bpm: Double, mainDurationSeconds: Int,
                      ratio: BreathRatio = .fourToSix) {
        self.bpm = bpm
        self.mainDurationSeconds = mainDurationSeconds
        self.breathRatio = ratio

        let config = SessionPhaseController.Config(
            mainDurationSeconds: mainDurationSeconds)
        var ctrl = SessionPhaseController(config: config)
        ctrl.start(at: Date())
        controller = ctrl

        isRunning = true
        isPaused = false
        scheduleTimer()
    }

    public func stop() {
        cancelTimer()
        controller = nil
        state = .idle
        isRunning = false
        isPaused = false
    }

    public func pause() {
        guard isRunning, !isPaused else { return }
        controller?.pause(at: Date())
        isPaused = true
    }

    public func resume() {
        guard isRunning, isPaused else { return }
        controller?.resume(at: Date())
        isPaused = false
    }

    /// Skip directly to reflection phase (e.g. early finish button).
    public func advanceToReflection() {
        // Force-set phase: stop normal timer loop; the view handles the reflection UI
        stop()
    }

    // MARK: - Timer

    private func scheduleTimer() {
        cancelTimer()
        let src = DispatchSource.makeTimerSource(queue: timerQueue)
        src.schedule(deadline: .now(), repeating: tickInterval,
                     leeway: .microseconds(500))
        src.setEventHandler { [weak self] in
            // Capture now on timerQueue for accuracy, then post to main actor.
            let now = Date()
            Task { @MainActor [weak self] in self?.processTick(now: now) }
        }
        src.resume()
        timer = src
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Tick (MainActor)

    private func processTick(now: Date) {
        guard var ctrl = controller else { return }
        let result = ctrl.tick(now: now)
        controller = ctrl   // write back mutated value

        if result.isComplete {
            cancelTimer()
            isRunning = false
        }

        state = buildPacerState(from: result, now: now)
    }

    // MARK: - PacerState construction

    private func buildPacerState(
        from result: SessionPhaseController.TickResult,
        now: Date
    ) -> PacerState {
        let cyclePos = result.phaseElapsed.truncatingRemainder(
            dividingBy: breathPeriod)
        let (breathPhase, breathProgress) = breathPhaseAndProgress(
            cyclePos: cyclePos)
        let ringScale = ringScaleFor(cyclePos: cyclePos)

        return PacerState(
            sessionPhase: result.phase,
            breathPhase: breathPhase,
            breathProgress: breathProgress,
            ringScale: ringScale,
            totalElapsed: result.totalElapsed,
            sessionPhaseElapsed: result.phaseElapsed,
            sessionPhaseRemaining: result.phaseRemaining
        )
    }

    // MARK: - Breath math

    private func recomputeBreathPeriod() {
        breathPeriod = 60.0 / max(bpm, 0.1)
        inhaleDuration = breathPeriod * breathRatio.inhaleFraction
        exhaleDuration = breathPeriod * breathRatio.exhaleFraction
    }

    private func breathPhaseAndProgress(
        cyclePos: Double
    ) -> (BreathPhase, Double) {
        if cyclePos < inhaleDuration {
            return (.inhale, cyclePos / inhaleDuration)
        } else {
            let exhalePos = cyclePos - inhaleDuration
            return (.exhale, exhalePos / exhaleDuration)
        }
    }

    /// Sinusoidal ring scale: 0.6 at start of inhale → 1.4 at end of inhale → 0.6 at end of exhale.
    private func ringScaleFor(cyclePos: Double) -> Double {
        let phase = (cyclePos / breathPeriod) * 2.0 * Double.pi - Double.pi / 2.0
        return 1.0 + 0.4 * sin(phase)
    }
}
