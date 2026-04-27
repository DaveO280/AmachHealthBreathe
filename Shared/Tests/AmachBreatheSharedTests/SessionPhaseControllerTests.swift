import XCTest
@testable import AmachBreatheShared

final class SessionPhaseControllerTests: XCTestCase {

    // Base timestamp — epoch for reproducibility
    let t0 = Date(timeIntervalSince1970: 0)

    func makeController(mainSecs: Int = 300) -> SessionPhaseController {
        var ctrl = SessionPhaseController(config: .init(mainDurationSeconds: mainSecs))
        ctrl.start(at: t0)
        return ctrl
    }

    // MARK: - 5-phase sequence

    func testInitialPhaseIsBaseline() {
        let ctrl = makeController()
        XCTAssertEqual(ctrl.currentPhase, .baseline)
    }

    func testBaselineTransitionsToWarmupAt30s() {
        var ctrl = makeController()
        let r = ctrl.tick(now: t0 + 30)
        XCTAssertEqual(r.phase, .warmup)
        XCTAssertEqual(r.transitionedTo, .warmup)
    }

    func testNoTransitionJustBefore30s() {
        var ctrl = makeController()
        let r = ctrl.tick(now: t0 + 29.9)
        XCTAssertEqual(r.phase, .baseline)
        XCTAssertNil(r.transitionedTo)
    }

    func testWarmupTransitionsToMainAt90s() {
        var ctrl = makeController()
        ctrl.tick(now: t0 + 30)     // → warmup
        let r = ctrl.tick(now: t0 + 90)
        XCTAssertEqual(r.phase, .main(durationSeconds: 300))
        XCTAssertEqual(r.transitionedTo, .main(durationSeconds: 300))
    }

    func testMainTransitionsToRecoveryAt390s() {
        var ctrl = makeController(mainSecs: 300)
        ctrl.tick(now: t0 + 30)     // → warmup
        ctrl.tick(now: t0 + 90)     // → main(300)
        let r = ctrl.tick(now: t0 + 390)
        XCTAssertEqual(r.phase, .recovery)
        XCTAssertEqual(r.transitionedTo, .recovery)
    }

    func testRecoveryTransitionsToReflectionAt420s() {
        var ctrl = makeController(mainSecs: 300)
        ctrl.tick(now: t0 + 30)
        ctrl.tick(now: t0 + 90)
        ctrl.tick(now: t0 + 390)
        let r = ctrl.tick(now: t0 + 420)
        XCTAssertEqual(r.phase, .reflection)
        XCTAssertEqual(r.transitionedTo, .reflection)
    }

    func testAllFivePhasesInSequence() {
        var ctrl = makeController(mainSecs: 300)
        // baseline (30s), warmup (60s), main (300s), recovery (30s), reflection
        let transitions = [30.0, 90.0, 390.0, 420.0]
        let expected: [SessionPhase] = [.warmup, .main(durationSeconds: 300), .recovery, .reflection]

        for (t, exp) in zip(transitions, expected) {
            let r = ctrl.tick(now: t0 + t)
            XCTAssertEqual(r.transitionedTo, exp, "At t=\(t) expected transition to \(exp)")
        }
    }

    func testPhaseRemainingCountsDown() {
        var ctrl = makeController()
        let r = ctrl.tick(now: t0 + 10)
        XCTAssertEqual(r.phaseRemaining!, 20, accuracy: 0.01)
    }

    func testTotalElapsedAccumulates() {
        var ctrl = makeController()
        let r = ctrl.tick(now: t0 + 50)
        XCTAssertEqual(r.totalElapsed, 50, accuracy: 0.01)
    }

    // MARK: - Pause / resume in each phase

    func testPauseFreezesElapsedInBaseline() {
        var ctrl = makeController()
        ctrl.pause(at: t0 + 10)           // paused at 10s into baseline
        let r = ctrl.tick(now: t0 + 20)   // 10s later — should still see 10s elapsed
        XCTAssertEqual(r.phaseElapsed, 10, accuracy: 0.01)
        XCTAssertEqual(r.phase, .baseline)
        XCTAssertNil(r.transitionedTo)     // no auto-advance while paused
    }

    func testResumeAfterPauseResumesFromCorrectElapsed() {
        var ctrl = makeController()
        ctrl.pause(at: t0 + 10)           // 10s elapsed
        ctrl.resume(at: t0 + 25)          // paused for 15s
        let r = ctrl.tick(now: t0 + 30)   // 5s after resume → total phase elapsed = 15s
        XCTAssertEqual(r.phaseElapsed, 15, accuracy: 0.01)
        XCTAssertEqual(r.phase, .baseline)
    }

    func testPauseDoesNotCountTowardTotalElapsed() {
        var ctrl = makeController()
        ctrl.pause(at: t0 + 10)
        ctrl.resume(at: t0 + 110)         // paused for 100s
        let r = ctrl.tick(now: t0 + 120)  // 10s after resume → total elapsed = 20s not 120s
        XCTAssertEqual(r.totalElapsed, 20, accuracy: 0.1)
    }

    func testPauseAndResumePreservesPhase() {
        var ctrl = makeController()
        ctrl.tick(now: t0 + 30)            // → warmup
        ctrl.pause(at: t0 + 60)            // 30s into warmup
        ctrl.resume(at: t0 + 120)          // paused 60s
        let r = ctrl.tick(now: t0 + 150)   // 30s after resume → phase elapsed = 60s
        // warmup target = 60s; 30s + 30s = 60s → should transition to main
        XCTAssertEqual(r.phase, .main(durationSeconds: 300))
    }

    func testPauseAcrossMultiplePhases() {
        var ctrl = makeController(mainSecs: 300)
        // Pause during baseline at 15s, resume after 50s
        ctrl.pause(at: t0 + 15)
        ctrl.resume(at: t0 + 65)
        // Now at t0+100: baseline elapsed = 15 + (100-65) = 50s → still in baseline
        var r = ctrl.tick(now: t0 + 80)  // 15s after resume → elapsed = 30s → transitions to warmup
        XCTAssertEqual(r.transitionedTo, .warmup)
        // Continue into warmup
        r = ctrl.tick(now: t0 + 140)     // 60s more → transition to main
        XCTAssertEqual(r.transitionedTo, .main(durationSeconds: 300))
    }

    func testDoublePauseIgnored() {
        var ctrl = makeController()
        ctrl.pause(at: t0 + 10)
        ctrl.pause(at: t0 + 20)  // second pause — should be ignored
        ctrl.resume(at: t0 + 30)
        let r = ctrl.tick(now: t0 + 35)  // 5s after resume → elapsed = 15s
        XCTAssertEqual(r.phaseElapsed, 15, accuracy: 0.01)
    }

    func testDoubleResumeIgnored() {
        var ctrl = makeController()
        ctrl.pause(at: t0 + 10)
        ctrl.resume(at: t0 + 20)
        ctrl.resume(at: t0 + 30)  // second resume — should be ignored
        let r = ctrl.tick(now: t0 + 25)
        XCTAssertEqual(r.phaseElapsed, 15, accuracy: 0.01)
    }
}

// MARK: - Date arithmetic helper

private extension Date {
    static func + (lhs: Date, rhs: Double) -> Date {
        lhs.addingTimeInterval(rhs)
    }
}
