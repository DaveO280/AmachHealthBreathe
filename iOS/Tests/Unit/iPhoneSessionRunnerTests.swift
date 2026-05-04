import XCTest
@testable import AmachBreathe
import AmachBreatheShared

/// Smoke test for the iPhone-only breathing session path. Exercises the
/// dispatch source timer (which used to trap because the Swift 6 closure
/// isolation in iPhoneMasterPhaseTimer.scheduleTimer inherited @MainActor and
/// fired off the non-MainActor timerQueue) and the AVAudioEngine setup in
/// iPhoneAudioPacer (which used to be invoked with `format: nil`).
@MainActor
final class iPhoneSessionRunnerTests: XCTestCase {

    func testStartSessionDoesNotCrash() async throws {
        let runner = iPhoneSessionRunner()
        runner.startSession(bpm: 5.5, durationSeconds: 60, ratio: .fourToSix)
        XCTAssertTrue(runner.isRunning)

        // Let the dispatch source fire ~30 ticks (60 Hz × 0.5 s) and the
        // audio pacer consume a few @Published state updates.
        try await Task.sleep(nanoseconds: 500_000_000)

        // After a few ticks the timer should have advanced into baseline,
        // proving the handler ran without trapping on actor isolation.
        XCTAssertGreaterThan(runner.pacerState.totalElapsed, 0)
        XCTAssertTrue(runner.pacerState.sessionPhase.isActive)

        runner.endSession()
        XCTAssertFalse(runner.isRunning)
    }
}
