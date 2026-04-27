import XCTest
@testable import AmachBreatheShared

/// Tests CalibrationEngine with synthetic RR data containing a planted oscillation
/// peak at each of the 6 candidate rates. Each fixture must be identified correctly.
final class CalibrationEngineTests: XCTestCase {

    let engine = CalibrationEngine()

    // MARK: - 6 fixtures: one planted peak per rate

    func testResonanceDetected_4_5_BPM() { assertResonance(plantedBPM: 4.5) }
    func testResonanceDetected_5_0_BPM() { assertResonance(plantedBPM: 5.0) }
    func testResonanceDetected_5_5_BPM() { assertResonance(plantedBPM: 5.5) }
    func testResonanceDetected_6_0_BPM() { assertResonance(plantedBPM: 6.0) }
    func testResonanceDetected_6_5_BPM() { assertResonance(plantedBPM: 6.5) }
    func testResonanceDetected_7_0_BPM() { assertResonance(plantedBPM: 7.0) }

    // MARK: - API surface

    func testFindResonance_returnsAllSixScores() {
        let samples = allSamples(plantedBPM: 5.5)
        let result = engine.findResonance(samples: samples)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.scores.count, 6)
    }

    func testFindResonance_insufficientData_skipsRate() {
        // Only one rate has enough data
        let samples: [Double: [Double]] = [5.5: syntheticRR(bpm: 5.5, count: 80, amplitude: 100)]
        let result = engine.findResonance(samples: samples)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.resonanceBPM, 5.5)
    }

    func testFindResonance_emptyInput_returnsNil() {
        XCTAssertNil(engine.findResonance(samples: [:]))
    }

    func testAmplitude_singleRate() {
        let rr = syntheticRR(bpm: 6.0, count: 60, amplitude: 80)
        let a = engine.amplitude(rrIntervals: rr, bpm: 6.0)
        XCTAssertNotNil(a)
        XCTAssertGreaterThan(a!, 0)
        // rawAmplitude is proportional to ms amplitude — just verify positive and finite
        XCTAssertFalse(a!.isNaN)
        XCTAssertFalse(a!.isInfinite)
    }

    func testAmplitude_insufficientData_returnsNil() {
        XCTAssertNil(engine.amplitude(rrIntervals: [800, 810], bpm: 5.5))
    }

    func testCalibrationRecord_roundTrip() throws {
        let samples = allSamples(plantedBPM: 5.5)
        let result = engine.findResonance(samples: samples)!
        let record = CalibrationRecord(result: result)
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(CalibrationRecord.self, from: data)
        XCTAssertEqual(decoded.resonanceBPM, record.resonanceBPM)
        XCTAssertFalse(decoded.needsRetest)  // just created
    }

    // MARK: - Helpers

    private func assertResonance(plantedBPM: Double, file: StaticString = #file, line: UInt = #line) {
        let samples = allSamples(plantedBPM: plantedBPM)
        let result = engine.findResonance(samples: samples)
        XCTAssertNotNil(result, "No result for planted BPM \(plantedBPM)", file: file, line: line)
        XCTAssertEqual(
            result!.resonanceBPM, plantedBPM, accuracy: 0.3,
            "Expected \(plantedBPM) BPM, got \(result!.resonanceBPM)",
            file: file, line: line
        )
    }

    /// Build one RR array per candidate BPM, with the planted BPM having highest amplitude.
    private func allSamples(plantedBPM: Double) -> [Double: [Double]] {
        var samples: [Double: [Double]] = [:]
        for bpm in CalibrationEngine.candidateBPMs {
            let amplitude: Double = (bpm == plantedBPM) ? 120.0 : 20.0
            samples[bpm] = syntheticRR(bpm: bpm, count: 80, amplitude: amplitude)
        }
        return samples
    }

    /// RR intervals (ms) oscillating at `bpm` with given peak-to-trough `amplitude`.
    private func syntheticRR(bpm: Double, count: Int, amplitude: Double) -> [Double] {
        let period = 60.0 / bpm
        var rr: [Double] = []
        var t = 0.0
        for _ in 0 ..< count {
            let v = 850.0 + amplitude * sin(2.0 * Double.pi * t / period)
            rr.append(v)
            t += 850.0 / 1000.0
        }
        return rr
    }
}
