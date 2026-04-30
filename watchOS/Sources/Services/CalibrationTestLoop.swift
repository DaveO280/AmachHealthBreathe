import Foundation
import Combine
import os
import AmachBreatheShared

/// Debug-only autonomous test driver that runs `WatchCalibrationRunner`
/// repeatedly to surface freezes, ring-scale glitches, and rate-transition
/// races. Activated by environment variables — never runs in normal builds.
///
/// Environment:
///   - CALIBRATION_TEST_LOOPS:     iteration count (e.g. "5"). Absent → disabled.
///   - CALIBRATION_RATE_SECONDS:   seconds per candidate (default 5 for fast loops).
///
/// All events are logged under subsystem "com.amach.AmachBreathe",
/// category "CalibrationTest" — stream with:
///     xcrun simctl spawn <udid> log stream \
///       --predicate 'subsystem == "com.amach.AmachBreathe"' \
///       --style compact
@MainActor
public final class CalibrationTestLoop {

    public static let shared = CalibrationTestLoop()

    private static let log = Logger(
        subsystem: "com.amach.AmachBreathe", category: "CalibrationTest")

    private weak var runner: WatchCalibrationRunner?
    private var cancellable: AnyCancellable?
    private var totalLoops: Int = 0
    private var currentLoop: Int = 0
    private var rateSeconds: TimeInterval = 5
    private var loopStart: Date?
    /// 2× the wall-clock budget for one full calibration; if a loop exceeds
    /// this, we declare a freeze and bail.
    private var freezeWatchdog: Timer?

    private init() {}

    /// Read environment, configure the runner, and kick off the loop. No-op
    /// if CALIBRATION_TEST_LOOPS isn't set.
    public func startIfRequested(runner: WatchCalibrationRunner) {
        let env = ProcessInfo.processInfo.environment
        guard let loopsStr = env["CALIBRATION_TEST_LOOPS"],
              let loops = Int(loopsStr), loops > 0 else { return }

        self.totalLoops = loops
        self.currentLoop = 0
        self.runner = runner

        if let secStr = env["CALIBRATION_RATE_SECONDS"],
           let sec = Double(secStr), sec > 0.5 {
            rateSeconds = sec
        }
        runner.sampleDurationPerRate = rateSeconds

        Self.log.info("TEST_LOOP_BEGIN loops=\(loops, privacy: .public) rateSec=\(self.rateSeconds, privacy: .public)")

        // Subscribe to calibrationState — when each run completes (or fails),
        // schedule the next.
        cancellable = runner.$calibrationState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.handleStateChange(state)
            }

        // Tiny delay so the runner is fully wired into the SwiftUI environment
        // before we drive it.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.startNextLoop()
        }
    }

    private func startNextLoop() {
        guard let runner else { return }
        guard currentLoop < totalLoops else {
            Self.log.info("TEST_LOOP_ALL_DONE loops=\(self.totalLoops, privacy: .public)")
            cancellable = nil
            freezeWatchdog?.invalidate()
            return
        }
        currentLoop += 1
        loopStart = Date()
        Self.log.info("TEST_LOOP_START iter=\(self.currentLoop, privacy: .public)/\(self.totalLoops, privacy: .public)")

        // Watchdog. Per-rate wall time is the rate window PLUS up to one full
        // breath cycle (60/bpm seconds) waiting for the next inhale boundary.
        // The breath sum dominates at small rateSeconds, so include it
        // explicitly — earlier `rateSeconds * 6` budgets fired falsely.
        let breathSum = CalibrationEngine.candidateBPMs.reduce(0.0) { $0 + 60.0 / $1 }
        let expected = rateSeconds * Double(CalibrationEngine.candidateBPMs.count) + breathSum
        let budget = expected * 1.5 + 10.0
        freezeWatchdog?.invalidate()
        freezeWatchdog = Timer.scheduledTimer(
            withTimeInterval: budget, repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                Self.log.error("TEST_LOOP_FREEZE iter=\(self.currentLoop, privacy: .public) — no completion within \(budget, privacy: .public)s; canceling")
                await self.runner?.cancel()
                // Give cancel() a beat then advance.
                try? await Task.sleep(nanoseconds: 500_000_000)
                self.startNextLoop()
            }
        }

        Task { @MainActor in
            await runner.start()
        }
    }

    private func handleStateChange(_ state: WatchCalibrationRunner.State) {
        switch state {
        case .complete(let record):
            let elapsed = loopStart.map { Date().timeIntervalSince($0) } ?? 0
            Self.log.info("TEST_LOOP_COMPLETE iter=\(self.currentLoop, privacy: .public) bpm=\(record.resonanceBPM, privacy: .public) elapsed=\(elapsed, privacy: .public)s")
            scheduleNext()
        case .failed:
            let elapsed = loopStart.map { Date().timeIntervalSince($0) } ?? 0
            Self.log.info("TEST_LOOP_FAILED iter=\(self.currentLoop, privacy: .public) elapsed=\(elapsed, privacy: .public)s (expected on simulator — no HK)")
            scheduleNext()
        case .idle, .running:
            break
        }
    }

    private func scheduleNext() {
        freezeWatchdog?.invalidate()
        freezeWatchdog = nil
        // Brief pause between iterations so the previous calibrationState=.complete/.failed
        // can settle and we can observe the runner returning to .idle in the harness.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            // The runner only accepts .start() when state == .idle, so reset.
            await self?.runner?.cancel()
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.startNextLoop()
        }
    }
}
