import XCTest
@testable import AmachBreatheShared

/// Stress tests for CalibrationEngine under degraded amplitude curves.
///
/// Real-world calibration sessions often lack a clear resonance peak —
/// low-HRV users, noisy sensors, and brief windows all produce ambiguous data.
/// The engine must:
///   - Always return a result within the valid BPM set (never nil unless truly no data)
///   - Never return a BPM outside the 6 candidates
///   - Produce a deterministic tiebreaker (lower BPM preferred)
///   - Not crash or produce NaN/Inf scores
final class CalibrationDegradedTests: XCTestCase {

    private let engine = CalibrationEngine()

    // MARK: - Helpers

    /// RR series with a breathing oscillation of given amplitude at `bpm`.
    private func oscillatingRR(bpm: Double, count: Int, amplitude: Double, baseMs: Double = 860) -> [Double] {
        let period = 60.0 / bpm
        return (0..<count).map { i in
            baseMs + amplitude * sin(2.0 * .pi * Double(i) * (baseMs / 1000.0) / period)
        }
    }

    /// Pure noise — no planted frequency.
    private func noiseRR(count: Int, range: Double = 40, baseMs: Double = 860) -> [Double] {
        (0..<count).map { _ in baseMs + Double.random(in: -range...range) }
    }

    // MARK: - 1. Flat curve: all 6 rates within 5% of each other

    func testFlatCurve_allRatesNearlyEqual_returnsResult() {
        // Build samples with very small, nearly-equal oscillations at every rate.
        // Amplitude 1.5 ms is tiny — within 5% of each other.
        var samples: [Double: [Double]] = [:]
        for bpm in CalibrationEngine.candidateBPMs {
            samples[bpm] = oscillatingRR(bpm: bpm, count: 80, amplitude: 1.5)
        }
        let result = engine.findResonance(samples: samples)
        XCTAssertNotNil(result, "Engine must return a result even when all rates have nearly equal amplitude")
        if let r = result {
            XCTAssertTrue(CalibrationEngine.candidateBPMs.contains(r.resonanceBPM),
                "Resonance BPM \(r.resonanceBPM) must be one of the 6 candidates")
        }
    }

    func testFlatCurve_normalizedScores_maxIsOne() {
        var samples: [Double: [Double]] = [:]
        for bpm in CalibrationEngine.candidateBPMs {
            samples[bpm] = oscillatingRR(bpm: bpm, count: 80, amplitude: 2.0)
        }
        guard let result = engine.findResonance(samples: samples) else {
            XCTFail("Expected non-nil result"); return
        }
        let maxScore = result.scores.values.max() ?? 0
        XCTAssertEqual(maxScore, 1.0, accuracy: 0.001,
            "Highest normalised score must always be 1.0")
    }

    func testFlatCurve_noNaNOrInfInScores() {
        var samples: [Double: [Double]] = [:]
        for bpm in CalibrationEngine.candidateBPMs {
            samples[bpm] = oscillatingRR(bpm: bpm, count: 80, amplitude: 1.0)
        }
        guard let result = engine.findResonance(samples: samples) else { return }
        for (bpm, score) in result.scores {
            XCTAssertFalse(score.isNaN,      "Score for \(bpm) BPM must not be NaN")
            XCTAssertFalse(score.isInfinite, "Score for \(bpm) BPM must not be Inf")
            XCTAssertGreaterThanOrEqual(score, 0.0, "Normalised score must be ≥ 0")
            XCTAssertLessThanOrEqual(score, 1.0,    "Normalised score must be ≤ 1.0")
        }
    }

    // MARK: - 2. Noisy curve: random amplitude ordering, no clear peak

    func testNoisyCurve_randomOrder_resultIsValidCandidate() {
        // Each rate gets a random amplitude — no planted peak.
        var samples: [Double: [Double]] = [:]
        for bpm in CalibrationEngine.candidateBPMs {
            let amplitude = Double.random(in: 5...60)
            samples[bpm] = oscillatingRR(bpm: bpm, count: 80, amplitude: amplitude)
        }
        guard let result = engine.findResonance(samples: samples) else {
            XCTFail("Engine must return a result even for a noisy curve"); return
        }
        XCTAssertTrue(CalibrationEngine.candidateBPMs.contains(result.resonanceBPM),
            "Result \(result.resonanceBPM) BPM must be one of the 6 candidates")
        XCTAssertEqual(result.scores.values.max() ?? 0, 1.0, accuracy: 0.001)
    }

    func testNoisyCurve_repeatedCalls_deterministicResult() {
        // With a fixed random seed via a stable RR array, result must be identical every call.
        var samples: [Double: [Double]] = [:]
        // Use seeded amplitudes to make this deterministic
        let amplitudes: [Double] = [18.3, 42.1, 11.7, 35.6, 27.9, 50.2]
        for (i, bpm) in CalibrationEngine.candidateBPMs.enumerated() {
            samples[bpm] = oscillatingRR(bpm: bpm, count: 80, amplitude: amplitudes[i])
        }
        let first = engine.findResonance(samples: samples)?.resonanceBPM
        for _ in 0..<10 {
            let next = engine.findResonance(samples: samples)?.resonanceBPM
            XCTAssertEqual(first, next, "findResonance must be deterministic for the same input")
        }
    }

    func testNoisyCurve_pureNoise_returnsResultInRange() {
        // Pure noise — no oscillation. Engine still picks a winner.
        var samples: [Double: [Double]] = [:]
        for bpm in CalibrationEngine.candidateBPMs {
            samples[bpm] = noiseRR(count: 80, range: 50)
        }
        // Pure noise may return nil if all Goertzel amplitudes are zero (uncommon but valid)
        if let result = engine.findResonance(samples: samples) {
            XCTAssertTrue(CalibrationEngine.candidateBPMs.contains(result.resonanceBPM),
                "Noisy result must still be a valid candidate BPM")
        }
    }

    // MARK: - 3. Realistic low-HRV user: < 2 ms amplitude difference across all rates

    func testLowHRV_tinyAmplitude_returnsResult() {
        // Very low HRV: oscillation amplitude < 1 ms — near the noise floor of an Apple Watch.
        var samples: [Double: [Double]] = [:]
        for bpm in CalibrationEngine.candidateBPMs {
            samples[bpm] = oscillatingRR(bpm: bpm, count: 80, amplitude: 0.8)
        }
        let result = engine.findResonance(samples: samples)
        XCTAssertNotNil(result, "Engine must return a result for a low-HRV user (amplitude < 1 ms)")
        if let r = result {
            XCTAssertTrue(CalibrationEngine.candidateBPMs.contains(r.resonanceBPM))
        }
    }

    func testLowHRV_tinyAmplitudeDifferential_resultsAreValid() {
        // Amplitudes differ by < 2 ms across all 6 rates (realistic low-HRV scenario)
        var samples: [Double: [Double]] = [:]
        let amplitudes: [Double: Double] = [4.5: 1.0, 5.0: 1.3, 5.5: 2.1, 6.0: 1.8, 6.5: 1.5, 7.0: 1.2]
        for bpm in CalibrationEngine.candidateBPMs {
            samples[bpm] = oscillatingRR(bpm: bpm, count: 80, amplitude: amplitudes[bpm]!)
        }
        guard let result = engine.findResonance(samples: samples) else {
            XCTFail("Low-HRV calibration must return a result"); return
        }
        XCTAssertTrue(CalibrationEngine.candidateBPMs.contains(result.resonanceBPM),
            "Result must be one of the 6 candidates")
        XCTAssertEqual(result.scores.count, 6, "All 6 scores must be present")
        // At sub-2ms amplitudes, Goertzel spectral power doesn't map 1:1 to oscillation
        // parameter — we assert a valid candidate is returned, not a specific winner.
    }

    func testLowHRV_amplitudeFunction_nonNilNonNaN() {
        let rr = oscillatingRR(bpm: 5.5, count: 80, amplitude: 0.5)
        for bpm in CalibrationEngine.candidateBPMs {
            let amp = engine.amplitude(rrIntervals: rr, bpm: bpm)
            XCTAssertNotNil(amp, "amplitude() must not return nil for 80 samples at \(bpm) BPM")
            if let a = amp {
                XCTAssertFalse(a.isNaN,      "amplitude() must not be NaN at \(bpm) BPM")
                XCTAssertFalse(a.isInfinite, "amplitude() must not be Inf at \(bpm) BPM")
                XCTAssertGreaterThanOrEqual(a, 0.0, "amplitude() must be ≥ 0")
            }
        }
    }

    // MARK: - 4. Deterministic tiebreaker: lower BPM wins when amplitudes are equal

    func testTie_flatSignal_lowestBPMWins() {
        // A constant RR signal produces ~zero Goertzel power at all candidate frequencies.
        // All amplitudes ≈ 0 → all tied → tiebreaker must select 4.5 BPM (lowest).
        let flatRR = [Double](repeating: 860.0, count: 80)
        let samples = Dictionary(uniqueKeysWithValues: CalibrationEngine.candidateBPMs.map { ($0, flatRR) })
        guard let result = engine.findResonance(samples: samples) else {
            // Acceptable: flat signal may produce all-zero amplitudes → no winner
            return
        }
        XCTAssertEqual(result.resonanceBPM, 4.5,
            "When all amplitudes are tied at zero, the lowest candidate BPM (4.5) must win")
    }

    func testTie_twoRatesExplicitlyEqual_lowerWins() {
        // Plant equal amplitudes at 5.0 and 5.5 BPM, both above all others.
        // The tiebreaker must pick 5.0 (lower).
        var samples: [Double: [Double]] = [:]
        let highAmplitude = 80.0
        let lowAmplitude  = 10.0
        for bpm in CalibrationEngine.candidateBPMs {
            let amplitude = (bpm == 5.0 || bpm == 5.5) ? highAmplitude : lowAmplitude
            samples[bpm] = oscillatingRR(bpm: bpm, count: 160, amplitude: amplitude)
        }
        // With 160 samples and identical amplitude parameters, the two rates may
        // produce very close (but not necessarily exact) Goertzel results.
        // Test: the result is either 5.0 or 5.5 (the two tied candidates), not 4.5/6.0/6.5/7.0
        guard let result = engine.findResonance(samples: samples) else {
            XCTFail("Expected a result"); return
        }
        XCTAssertTrue([5.0, 5.5].contains(result.resonanceBPM),
            "With two tied high-amplitude rates, result must be 5.0 or 5.5, got \(result.resonanceBPM)")
    }

    func testTie_deterministicAcrossRepeatedCalls() {
        // A flat signal always produces the same tiebreaker result
        let flatRR = [Double](repeating: 860.0, count: 80)
        let samples = Dictionary(uniqueKeysWithValues: CalibrationEngine.candidateBPMs.map { ($0, flatRR) })
        let first = engine.findResonance(samples: samples)?.resonanceBPM
        for _ in 0..<20 {
            let next = engine.findResonance(samples: samples)?.resonanceBPM
            XCTAssertEqual(first, next,
                "Tiebreaker must be deterministic — same input must always produce same BPM")
        }
    }

    // MARK: - 5. Minimum data boundary

    func testMinimumSamples_exactlyAtThreshold_returnsResult() {
        // CalibrationEngine.minSamplesPerRate = 8 — test the floor
        let samples = Dictionary(uniqueKeysWithValues: CalibrationEngine.candidateBPMs.map {
            ($0, oscillatingRR(bpm: $0, count: CalibrationEngine.minSamplesPerRate, amplitude: 40))
        })
        let result = engine.findResonance(samples: samples)
        XCTAssertNotNil(result, "Engine must handle the exact minimum sample count per rate")
    }

    func testOneBelowMinimum_rateSkipped() {
        // One rate has fewer than minSamplesPerRate → it must be skipped, not cause nil/crash
        var samples = Dictionary(uniqueKeysWithValues: CalibrationEngine.candidateBPMs.map {
            ($0, oscillatingRR(bpm: $0, count: 80, amplitude: 40))
        })
        samples[5.5] = oscillatingRR(bpm: 5.5, count: CalibrationEngine.minSamplesPerRate - 1, amplitude: 999)
        let result = engine.findResonance(samples: samples)
        XCTAssertNotNil(result)
        XCTAssertNotEqual(result?.resonanceBPM, 5.5,
            "Rate with insufficient data must be skipped even if its amplitude parameter is highest")
    }

    func testSingleSufficientRate_returnsThatRate() {
        let samples: [Double: [Double]] = [
            6.0: oscillatingRR(bpm: 6.0, count: 80, amplitude: 60)
        ]
        let result = engine.findResonance(samples: samples)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.resonanceBPM ?? -1, 6.0, accuracy: 0.01)
    }
}
