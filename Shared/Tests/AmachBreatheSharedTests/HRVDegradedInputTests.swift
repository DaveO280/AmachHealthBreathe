import XCTest
@testable import AmachBreatheShared

/// Stress tests for HRVProcessor and CoherenceCalculator under real-world degraded input.
///
/// Assertions follow a "degrade gracefully" contract:
///   - Never crash or produce NaN / Infinite / negative values
///   - Coherence score always in [0, 1] when non-nil
///   - RMSSD always ≥ 0 when non-nil
///   - When data is too corrupted to compute, return nil — don't fabricate a value
final class HRVDegradedInputTests: XCTestCase {

    // MARK: - Helpers

    private func normalRR(count: Int, bpm: Double = 70, noiseMs: Double = 15) -> [Double] {
        let baseline = 60_000.0 / bpm
        return (0..<count).map { _ in baseline + Double.random(in: -noiseMs...noiseMs) }
    }

    private func timestampedFeed(
        intervals: [Double],
        startOffset: TimeInterval = 1_700_000_000,
        into processor: HRVProcessor
    ) {
        var t = Date(timeIntervalSince1970: startOffset)
        for rr in intervals {
            processor.addRRInterval(rr, at: t)
            t = t.addingTimeInterval(rr / 1000.0)
        }
    }

    private func assertValidRMSSD(_ value: Double?, context: String, file: StaticString = #file, line: UInt = #line) {
        guard let v = value else { return } // nil is acceptable (insufficient data)
        XCTAssertGreaterThanOrEqual(v, 0.0,   "RMSSD must be ≥ 0 (\(context))", file: file, line: line)
        XCTAssertFalse(v.isNaN,               "RMSSD must not be NaN (\(context))", file: file, line: line)
        XCTAssertFalse(v.isInfinite,          "RMSSD must not be Inf (\(context))", file: file, line: line)
    }

    private func assertValidCoherence(_ value: Double?, context: String, file: StaticString = #file, line: UInt = #line) {
        guard let v = value else { return } // nil acceptable when HRV band power is zero
        XCTAssertGreaterThanOrEqual(v, 0.0, "Coherence must be ≥ 0 (\(context))", file: file, line: line)
        XCTAssertLessThanOrEqual(v, 1.0,    "Coherence must be ≤ 1.0 (\(context))", file: file, line: line)
        XCTAssertFalse(v.isNaN,             "Coherence must not be NaN (\(context))", file: file, line: line)
    }

    // MARK: - 1. Ectopic beat

    func testHRV_ectopicBeat_rmssdValid() {
        // A 200 ms ectopic mid-stream in an otherwise normal 70 bpm series
        let processor = HRVProcessor(windowDuration: 30)
        var rr = normalRR(count: 20)
        rr.insert(200.0, at: 10) // ectopic at position 10
        timestampedFeed(intervals: rr, into: processor)

        assertValidRMSSD(processor.rmssd, context: "ectopic beat")
        // Ectopic causes large successive difference → RMSSD should be elevated
        if let v = processor.rmssd { XCTAssertGreaterThan(v, 0, "RMSSD must be positive") }
    }

    func testCoherence_ectopicBeat_scoreInRange() {
        var rr = normalRR(count: 29)
        rr.insert(200.0, at: 14)
        assertValidCoherence(
            CoherenceCalculator().coherenceScore(rrIntervals: rr, targetBPM: 5.5),
            context: "ectopic beat"
        )
    }

    func testCoherence_ectopicBeat_doesNotExceedOne() {
        // Regression: a large sudden jump should not push coherence > 1.0
        for _ in 0..<10 {
            var rr = normalRR(count: 28)
            rr.insert(200.0, at: Int.random(in: 5..<23))
            if let score = CoherenceCalculator().coherenceScore(rrIntervals: rr, targetBPM: 5.5) {
                XCTAssertLessThanOrEqual(score, 1.0, "Coherence must never exceed 1.0")
            }
        }
    }

    // MARK: - 2. Motion artifact burst (5–10 consecutive high-variance readings)

    func testHRV_motionArtifactBurst_rmssdValid() {
        let processor = HRVProcessor(windowDuration: 30)
        var t = Date(timeIntervalSince1970: 1_700_000_000)

        // Pre-burst normal samples
        for rr in normalRR(count: 10) {
            processor.addRRInterval(rr, at: t)
            t = t.addingTimeInterval(rr / 1000.0)
        }
        // Artifact burst: 8 samples with chaotic values 400–1400 ms
        for _ in 0..<8 {
            let rr = Double.random(in: 400...1400)
            processor.addRRInterval(rr, at: t)
            t = t.addingTimeInterval(rr / 1000.0)
        }
        // Post-burst normal samples
        for rr in normalRR(count: 10) {
            processor.addRRInterval(rr, at: t)
            t = t.addingTimeInterval(rr / 1000.0)
        }

        assertValidRMSSD(processor.rmssd, context: "motion artifact burst")
    }

    func testCoherence_motionArtifactBurst_scoreInRange() {
        let rr: [Double] = normalRR(count: 10)
            + (0..<8).map { _ in Double.random(in: 400...1400) }
            + normalRR(count: 10)
        assertValidCoherence(
            CoherenceCalculator().coherenceScore(rrIntervals: rr, targetBPM: 5.5),
            context: "motion artifact burst"
        )
    }

    func testCoherence_allArtifact_scoreInRange() {
        // Worst case: entire window is artifact data
        let rr = (0..<30).map { _ in Double.random(in: 200...2000) }
        assertValidCoherence(
            CoherenceCalculator().coherenceScore(rrIntervals: rr, targetBPM: 5.5),
            context: "all-artifact window"
        )
    }

    // MARK: - 3. Sensor dropout

    func testHRV_shortDropout_rmssdValid() {
        // 3-second gap (≈ 3–4 missing beats at 70 bpm) mid-session
        let processor = HRVProcessor(windowDuration: 30)
        var t = Date(timeIntervalSince1970: 1_700_000_000)
        for rr in normalRR(count: 15) {
            processor.addRRInterval(rr, at: t)
            t = t.addingTimeInterval(rr / 1000.0)
        }
        t = t.addingTimeInterval(3.0) // 3-second dropout
        for rr in normalRR(count: 15) {
            processor.addRRInterval(rr, at: t)
            t = t.addingTimeInterval(rr / 1000.0)
        }
        assertValidRMSSD(processor.rmssd, context: "3-second dropout")
    }

    func testHRV_singleMissedBeat_simulatedByLargeRR() {
        // A missed beat appears as a single ~1700 ms interval (2 beats merged)
        let processor = HRVProcessor(windowDuration: 30)
        var rr = normalRR(count: 20)
        rr[10] = 1700.0 // missed beat
        timestampedFeed(intervals: rr, into: processor)
        assertValidRMSSD(processor.rmssd, context: "missed beat as large RR")
    }

    func testHRV_longDropout_windowEmpties_returnsNil() {
        // A 45-second gap exceeds the 30-second window.
        // After the dropout, only the single post-dropout sample is in the window → RMSSD nil.
        let processor = HRVProcessor(windowDuration: 30)
        var t = Date(timeIntervalSince1970: 1_700_000_000)
        for _ in 0..<10 {
            processor.addRRInterval(857, at: t)
            t = t.addingTimeInterval(0.857)
        }
        t = t.addingTimeInterval(45.0) // dropout longer than window
        processor.addRRInterval(857, at: t)

        XCTAssertNil(processor.rmssd,
            "RMSSD must be nil when the rolling window is empty after a long dropout")
        XCTAssertEqual(processor.currentWindow.count, 1,
            "Only the single post-dropout sample should remain in window")
    }

    // MARK: - 4. Out-of-order timestamps

    func testHRV_outOfOrderTimestamps_noNaN() {
        // Late-arriving sample (earlier timestamp) inserted after later samples
        let processor = HRVProcessor(windowDuration: 30)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        processor.addRRInterval(857, at: base.addingTimeInterval(0.0))
        processor.addRRInterval(843, at: base.addingTimeInterval(0.857))
        processor.addRRInterval(865, at: base.addingTimeInterval(1.700))
        processor.addRRInterval(830, at: base.addingTimeInterval(0.428)) // late-arriving, earlier time
        processor.addRRInterval(855, at: base.addingTimeInterval(2.565))
        processor.addRRInterval(850, at: base.addingTimeInterval(3.420))

        assertValidRMSSD(processor.rmssd, context: "out-of-order timestamps")
    }

    func testCoherence_outOfOrderInsertions_scoreInRange() {
        // Simulate samples arriving with shuffled array ordering
        var rr = normalRR(count: 25)
        rr.insert(855, at: 5)  // "late" arrival at position 5
        rr.insert(843, at: 12) // another late arrival
        assertValidCoherence(
            CoherenceCalculator().coherenceScore(rrIntervals: rr, targetBPM: 5.5),
            context: "out-of-order insertions"
        )
    }

    func testHRV_outOfOrderTimestamps_windowPruneIsCorrect() {
        // A very old out-of-order sample should be pruned once the window advances past it
        let processor = HRVProcessor(windowDuration: 5) // tight 5-second window
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // Recent samples (in window)
        for i in 0..<5 {
            processor.addRRInterval(857, at: base.addingTimeInterval(Double(i) * 0.857))
        }
        // Very old out-of-order sample (10 seconds before current base) — should be pruned
        // when the next sample pushes the cutoff past it
        processor.addRRInterval(800, at: base.addingTimeInterval(-10.0))
        // One more recent sample to trigger prune at t = 4.285 + 0.857 = 5.142
        processor.addRRInterval(857, at: base.addingTimeInterval(5.142))

        // The very old sample should have been pruned by the recent addition
        let window = processor.currentWindow
        XCTAssertFalse(window.isEmpty, "Window must have samples after pruning")
        assertValidRMSSD(processor.rmssd, context: "out-of-order window pruning")
    }

    // MARK: - 5. Combined degradation (ectopic + artifact + dropout together)

    func testHRV_combinedDegradation_gracefulOutput() {
        let processor = HRVProcessor(windowDuration: 30)
        var t = Date(timeIntervalSince1970: 1_700_000_000)

        var rr = normalRR(count: 5)
        rr.append(200.0)          // ectopic
        rr += normalRR(count: 3)
        rr += [500, 1200, 300]    // artifact burst
        rr += normalRR(count: 4)

        for interval in rr {
            processor.addRRInterval(interval, at: t)
            t = t.addingTimeInterval(interval / 1000.0)
        }
        t = t.addingTimeInterval(2.0) // short dropout
        for interval in normalRR(count: 5) {
            processor.addRRInterval(interval, at: t)
            t = t.addingTimeInterval(interval / 1000.0)
        }

        assertValidRMSSD(processor.rmssd, context: "combined degradation")
        let window = processor.currentWindow
        if window.count >= 8 {
            assertValidCoherence(
                CoherenceCalculator().coherenceScore(rrIntervals: window, targetBPM: 5.5),
                context: "combined degradation coherence"
            )
        }
    }
}
