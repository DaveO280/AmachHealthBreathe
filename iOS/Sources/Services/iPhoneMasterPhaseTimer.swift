import Foundation
import Combine
import AmachBreatheShared

/// iPhone-side 60 Hz phase timer — identical logic to the watchOS MasterPhaseTimer,
/// reproduced here because MasterPhaseTimer lives in the watchOS target.
@MainActor
final class iPhoneMasterPhaseTimer: ObservableObject {

    @Published private(set) var state: PacerState = .idle
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isPaused: Bool = false

    var bpm: Double = 5.5 { didSet { recomputeBreathPeriod() } }
    var mainDurationSeconds: Int = 300
    var breathRatio: BreathRatio = .fourToSix { didSet { recomputeBreathPeriod() } }

    private var controller: SessionPhaseController?
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(
        label: "com.amach.breathe.iphone.masterTimer", qos: .userInteractive)

    private var breathPeriod: TimeInterval = 60.0 / 5.5
    private var inhaleDuration: TimeInterval = 0
    private var exhaleDuration: TimeInterval = 0
    private let tickInterval: TimeInterval = 1.0 / 60.0

    init() { recomputeBreathPeriod() }

    func start(bpm: Double, mainDurationSeconds: Int, ratio: BreathRatio = .fourToSix) {
        self.bpm = bpm
        self.mainDurationSeconds = mainDurationSeconds
        self.breathRatio = ratio

        let config = SessionPhaseController.Config(mainDurationSeconds: mainDurationSeconds)
        var ctrl = SessionPhaseController(config: config)
        ctrl.start(at: Date())
        controller = ctrl

        isRunning = true
        isPaused = false
        scheduleTimer()
    }

    func stop() {
        cancelTimer()
        controller = nil
        state = .idle
        isRunning = false
        isPaused = false
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        controller?.pause(at: Date())
        isPaused = true
    }

    func resume() {
        guard isRunning, isPaused else { return }
        controller?.resume(at: Date())
        isPaused = false
    }

    private func scheduleTimer() {
        cancelTimer()
        let src = DispatchSource.makeTimerSource(queue: timerQueue)
        src.schedule(deadline: .now(), repeating: tickInterval, leeway: .microseconds(500))
        // The handler runs on `timerQueue` (non-MainActor). Type the closure as
        // @Sendable explicitly so Swift 6 doesn't inherit the class's @MainActor
        // isolation and trap on entry when DispatchSource invokes it.
        let handler: @Sendable () -> Void = { [weak self] in
            let now = Date()
            Task { @MainActor in
                self?.processTick(now: now)
            }
        }
        src.setEventHandler(handler: handler)
        src.resume()
        timer = src
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }

    private func processTick(now: Date) {
        guard var ctrl = controller else { return }
        let result = ctrl.tick(now: now)
        controller = ctrl

        if result.isComplete { cancelTimer(); isRunning = false }
        state = buildPacerState(from: result)
    }

    private func buildPacerState(from result: SessionPhaseController.TickResult) -> PacerState {
        // Drive the breath cycle from totalElapsed (continuous across phase
        // transitions, already excludes paused intervals) rather than
        // phaseElapsed, which resets at every phase boundary and would snap
        // the ring back to the start of an inhale mid-breath.
        let cyclePos = result.totalElapsed.truncatingRemainder(dividingBy: breathPeriod)
        let (breathPhase, breathProgress) = breathPhaseAndProgress(cyclePos: cyclePos)
        return PacerState(
            sessionPhase: result.phase,
            breathPhase: breathPhase,
            breathProgress: breathProgress,
            ringScale: ringScaleFor(cyclePos: cyclePos),
            totalElapsed: result.totalElapsed,
            sessionPhaseElapsed: result.phaseElapsed,
            sessionPhaseRemaining: result.phaseRemaining
        )
    }

    private func recomputeBreathPeriod() {
        breathPeriod = 60.0 / max(bpm, 0.1)
        inhaleDuration = breathPeriod * breathRatio.inhaleFraction
        exhaleDuration = breathPeriod * breathRatio.exhaleFraction
    }

    private func breathPhaseAndProgress(cyclePos: Double) -> (BreathPhase, Double) {
        if cyclePos < inhaleDuration {
            return (.inhale, cyclePos / inhaleDuration)
        } else {
            let exhalePos = cyclePos - inhaleDuration
            return (.exhale, exhalePos / exhaleDuration)
        }
    }

    private func ringScaleFor(cyclePos: Double) -> Double {
        let phase = (cyclePos / breathPeriod) * 2.0 * Double.pi - Double.pi / 2.0
        return 1.0 + 0.4 * sin(phase)
    }
}
