import XCTest
@testable import AmachBreatheShared

/// Synthetic 15-minute session performance regression suite.
///
/// These tests model the processing pipeline downstream of HKHeartbeatSeriesQuery.
/// HKHeartbeatSeriesQuery itself is HealthKit-platform-only (not testable in SPM);
/// these tests verify the consumer — HRVProcessor and CoherenceCalculator — stays
/// within timing budgets appropriate for Apple Watch Series 4 real-time use.
///
/// Battery-proxy methodology:
///   Apple Watch Series 4 has a ~300 mAh / 1.55 V battery (≈ 0.465 Wh).
///   5% of that over 15 minutes = 0.023 Wh.
///   If signal processing has < 5% CPU duty cycle during a session (i.e. active CPU
///   time < 45 s over a 900 s session), power draw from processing is well within budget.
///   macOS test machines are ~10–20× faster than Series 4; we assert macOS elapsed < 1 s
///   for 900 calls, implying Series 4 estimate < 20 s — under the 45 s threshold.
final class PerformanceRegressionTests: XCTestCase {

    // MARK: - Helpers

    /// Generate synthetic RR intervals (ms) with uniform noise.
    private func syntheticRR(count: Int, bpm: Double = 60, noiseMs: Double = 20) -> [Double] {
        let baseline = 60_000.0 / bpm
        return (0..<count).map { _ in baseline + Double.random(in: -noiseMs...noiseMs) }
    }

    // MARK: - HRV processor: window stays bounded

    func testHRVProcessorWindowStaysBounded() {
        let processor = HRVProcessor(windowDuration: 30)
        let rr = syntheticRR(count: 900) // 15 min at 60 bpm
        var t = Date(timeIntervalSince1970: 1_700_000_000)

        for interval in rr {
            processor.addRRInterval(interval, at: t)
            t = t.addingTimeInterval(interval / 1000.0)
        }

        // 30-second window at 60 bpm: at most ~30 beats + small margin
        XCTAssertLessThanOrEqual(processor.currentWindow.count, 35,
            "HRVProcessor window must not grow unboundedly after 15-min feed")
        XCTAssertNotNil(processor.rmssd,
            "RMSSD must be computable after a full 15-min session")
    }

    /// Verifies there is no lock-stall when all intervals arrive at the same timestamp
    /// (models a burst delivery, e.g. initial HKHeartbeatSeriesQuery batch).
    func testHRVProcessorHandlesRapidFireWithoutStall() {
        let processor = HRVProcessor(windowDuration: 30)
        let rr = syntheticRR(count: 900)
        let t = Date(timeIntervalSince1970: 1_700_000_000)

        let start = CFAbsoluteTimeGetCurrent()
        for interval in rr { processor.addRRInterval(interval, at: t) }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(elapsed, 0.5,
            "Rapid-fire 900-sample feed must complete in < 500 ms (no lock stall)")
    }

    // MARK: - Coherence calculator: per-call timing

    func testCoherenceCalculatorTimingBudget_30SecondWindow() {
        // 30-second rolling window at 60 bpm ≈ 30 RR intervals → interpolated to ~120 samples
        let coherence = CoherenceCalculator()
        let window = syntheticRR(count: 30)

        let iterations = 100
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = coherence.coherenceScore(rrIntervals: window, targetBPM: 5.5)
        }
        let perCallMs = (CFAbsoluteTimeGetCurrent() - start) / Double(iterations) * 1000

        // macOS budget: < 10 ms/call. Series 4 estimate: < 100–200 ms — well within real-time budget
        XCTAssertLessThan(perCallMs, 10.0,
            "CoherenceCalculator per-call time \(String(format: "%.2f", perCallMs)) ms exceeds 10 ms macOS budget")
    }

    // MARK: - Full pipeline (15-minute simulation)

    /// Drives HRVProcessor + CoherenceCalculator through 900 HR samples (15 min at 60 bpm),
    /// computing coherence after each new sample exactly as the live session does.
    func testFullSessionPipeline_15Minutes() {
        let hrv = HRVProcessor(windowDuration: 30)
        let coherence = CoherenceCalculator()
        var t = Date(timeIntervalSince1970: 1_700_000_000)
        let rr = syntheticRR(count: 900)

        var scores: [Double] = []
        let start = CFAbsoluteTimeGetCurrent()

        for interval in rr {
            hrv.addRRInterval(interval, at: t)
            t = t.addingTimeInterval(interval / 1000.0)
            let window = hrv.currentWindow
            if window.count >= 8, let s = coherence.coherenceScore(rrIntervals: window, targetBPM: 5.5) {
                scores.append(s)
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start

        // < 2 s on macOS. Series 4 estimate < 40 s for 900-s session → duty cycle < 4.5% < 5% spec
        XCTAssertLessThan(elapsed, 2.0,
            "Full 15-min pipeline took \(String(format: "%.3f", elapsed)) s — exceeds 2 s macOS budget")
        XCTAssertFalse(scores.isEmpty, "Coherence scores must be produced during 15-min session")
        XCTAssertTrue(scores.allSatisfy { $0 >= 0 && $0 <= 1.0 },
            "All coherence scores must be in [0, 1]")
    }

    // MARK: - Battery proxy: CPU duty-cycle estimate

    /// Models 900 coherence computations (one per HR beat in a 15-min session).
    /// This is the dominant CPU cost on the signal-processing path.
    /// Assertion validates the duty-cycle proxy is within the 5% Watch battery spec.
    func testBatteryProxyCPUDutyCycle() {
        let coherence = CoherenceCalculator()
        let window = syntheticRR(count: 30) // 30-s rolling window

        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<900 {
            _ = coherence.coherenceScore(rrIntervals: window, targetBPM: 5.5)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        // macOS < 1 s → Series 4 estimate 10–20 s < 45 s (5% of 900 s session)
        XCTAssertLessThan(elapsed, 1.0,
            "900-call CPU proxy \(String(format: "%.3f", elapsed)) s exceeds macOS budget; " +
            "implies > 5% Watch battery duty-cycle risk")
    }

    /// Validates coherence at candidate BPMs — models calibration scan cost.
    func testResonanceScanTiming() {
        let coherence = CoherenceCalculator()
        let window = syntheticRR(count: 120, bpm: 60, noiseMs: 15) // 2-minute calibration window

        let start = CFAbsoluteTimeGetCurrent()
        let result = coherence.resonanceBPM(rrIntervals: window)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertNotNil(result, "resonanceBPM must return a result with 120 samples")
        XCTAssertLessThan(elapsed, 0.1, "6-candidate resonance scan must complete in < 100 ms")
    }

    // MARK: - XCTest measure blocks (recorded in test navigator for regression tracking)

    func testMeasureCoherenceCalculation() {
        let coherence = CoherenceCalculator()
        let window = syntheticRR(count: 30)
        measure { _ = coherence.coherenceScore(rrIntervals: window, targetBPM: 5.5) }
    }

    func testMeasureHRVRMSSD() {
        let processor = HRVProcessor(windowDuration: 30)
        let rr = syntheticRR(count: 30)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for (i, interval) in rr.enumerated() {
            processor.addRRInterval(interval, at: base.addingTimeInterval(Double(i)))
        }
        measure { _ = processor.rmssd }
    }

    func testMeasureFullPipelineOneBeat() {
        let hrv = HRVProcessor(windowDuration: 30)
        let coherence = CoherenceCalculator()
        // Pre-fill to steady state
        let rr = syntheticRR(count: 30)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for (i, interval) in rr.enumerated() {
            hrv.addRRInterval(interval, at: base.addingTimeInterval(Double(i)))
        }
        measure {
            hrv.addRRInterval(1000, at: base.addingTimeInterval(30))
            _ = coherence.coherenceScore(rrIntervals: hrv.currentWindow, targetBPM: 5.5)
        }
    }
}
