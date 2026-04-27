import XCTest
@testable import AmachBreatheShared

final class CoherenceCalculatorTests: XCTestCase {

    let calculator = CoherenceCalculator(sampleRate: 4.0)

    // MARK: - Basic behavior

    func testCoherence_insufficientData_returnsNil() {
        let result = calculator.coherenceScore(rrIntervals: [800, 810, 790], targetBPM: 5.5)
        XCTAssertNil(result)
    }

    func testCoherence_syntheticOscillation_highScore() {
        // Generate synthetic RR series oscillating at exactly 5.5 BPM (0.0917 Hz)
        // with 300 ms amplitude — should produce a high coherence score
        let rr = syntheticRR(bpm: 5.5, count: 60, baseRR: 850, amplitude: 80)
        let score = calculator.coherenceScore(rrIntervals: rr, targetBPM: 5.5)
        XCTAssertNotNil(score)
        XCTAssertGreaterThan(score!, 0.5, "High-amplitude oscillation should yield coherence > 0.5")
    }

    func testCoherence_flatSignal_lowScore() {
        // Constant RR (no variability) → near-zero coherence
        let rr = [Double](repeating: 850, count: 40)
        let score = calculator.coherenceScore(rrIntervals: rr, targetBPM: 5.5)
        // With no power at any freq, result is nil or 0
        if let score { XCTAssertLessThan(score, 0.2) }
    }

    func testCoherence_wrongFreq_lowScore() {
        // Series oscillating at 5.5 BPM; queried at 7.0 BPM → lower score
        let rrAt5_5 = syntheticRR(bpm: 5.5, count: 60, baseRR: 850, amplitude: 80)
        let score5_5 = calculator.coherenceScore(rrIntervals: rrAt5_5, targetBPM: 5.5)!
        let score7_0 = calculator.coherenceScore(rrIntervals: rrAt5_5, targetBPM: 7.0)!
        XCTAssertGreaterThan(score5_5, score7_0)
    }

    func testCoherence_scoreInRange() {
        let rr = syntheticRR(bpm: 6.0, count: 50, baseRR: 850, amplitude: 60)
        let score = calculator.coherenceScore(rrIntervals: rr, targetBPM: 6.0)!
        XCTAssertGreaterThanOrEqual(score, 0.0)
        XCTAssertLessThanOrEqual(score, 1.0)
    }

    // MARK: - Resonance detection

    func testResonanceBPM_findsCorrectRate() {
        let rr = syntheticRR(bpm: 5.5, count: 80, baseRR: 850, amplitude: 100)
        let result = calculator.resonanceBPM(rrIntervals: rr)
        XCTAssertNotNil(result)
        // Best BPM should be 5.5 (or the closest candidate)
        XCTAssertEqual(result!.resonanceBPM, 5.5, accuracy: 0.6)
    }

    func testResonanceBPM_insufficientData_returnsNil() {
        XCTAssertNil(calculator.resonanceBPM(rrIntervals: [800, 810]))
    }

    // MARK: - Helpers

    /// Generates synthetic RR intervals oscillating at targetBPM.
    private func syntheticRR(bpm: Double, count: Int, baseRR: Double, amplitude: Double) -> [Double] {
        let period = 60.0 / bpm  // seconds
        var result: [Double] = []
        var t = 0.0
        for _ in 0 ..< count {
            let rr = baseRR + amplitude * sin(2.0 * Double.pi * t / period)
            result.append(rr)
            t += baseRR / 1000.0  // advance by approximate RR duration
        }
        return result
    }
}
