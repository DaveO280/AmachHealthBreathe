import XCTest
@testable import AmachBreatheShared

/// Verifies that CalibrationEngine always returns a BPM from the same candidate set
/// used by WatchCalibrationRunner — i.e. the result is always one of candidateBPMs.
final class CalibrationConsistencyTests: XCTestCase {

    let engine = CalibrationEngine()

    // MARK: - Fixtures

    private func syntheticRR(bpm: Double, count: Int = 80, amplitude: Double = 80) -> [Double] {
        let periodMs = 60000.0 / bpm
        let baseRR = 850.0
        return (0..<count).map { i in
            baseRR + amplitude * sin(2 * .pi * Double(i) / (periodMs / 850.0))
        }
    }

    private func allSamples(plantedBPM: Double) -> [Double: [Double]] {
        Dictionary(uniqueKeysWithValues: CalibrationEngine.candidateBPMs.map { bpm in
            let amp: Double = bpm == plantedBPM ? 100 : 5
            return (bpm, syntheticRR(bpm: bpm, count: 80, amplitude: amp))
        })
    }

    // MARK: - Result is always a candidate BPM

    func testResultBPMIsAlwaysCandidate() {
        for planted in CalibrationEngine.candidateBPMs {
            let result = engine.findResonance(samples: allSamples(plantedBPM: planted))
            XCTAssertNotNil(result, "Expected result for planted BPM \(planted)")
            guard let bpm = result?.resonanceBPM else { continue }
            XCTAssertTrue(
                CalibrationEngine.candidateBPMs.contains(bpm),
                "resonanceBPM \(bpm) not in candidateBPMs"
            )
        }
    }

    // MARK: - Scores stored for all 6 rates

    func testScoresContainAllCandidates() {
        for planted in CalibrationEngine.candidateBPMs {
            let result = engine.findResonance(samples: allSamples(plantedBPM: planted))
            guard let scores = result?.scores else {
                XCTFail("No result for planted BPM \(planted)")
                continue
            }
            for candidate in CalibrationEngine.candidateBPMs {
                XCTAssertNotNil(scores[candidate],
                    "Missing score for candidate \(candidate) when planted=\(planted)")
            }
        }
    }

    // MARK: - Scores are normalized 0–1

    func testScoresNormalized() {
        let result = engine.findResonance(samples: allSamples(plantedBPM: 6.0))
        guard let scores = result?.scores else { return XCTFail("No result") }
        for (bpm, score) in scores {
            XCTAssertGreaterThanOrEqual(score, 0.0, "Score \(score) at \(bpm) < 0")
            XCTAssertLessThanOrEqual(score, 1.0 + 1e-9, "Score \(score) at \(bpm) > 1")
        }
        // Max score == 1.0 (the planted peak)
        let maxScore = scores.values.max() ?? 0
        XCTAssertEqual(maxScore, 1.0, accuracy: 0.001)
    }

    // MARK: - CalibrationRecord wraps ResonanceFrequencyResult correctly

    func testCalibrationRecordBPMMatchesResult() {
        for planted in CalibrationEngine.candidateBPMs {
            guard let result = engine.findResonance(samples: allSamples(plantedBPM: planted)) else {
                XCTFail("No result for planted BPM \(planted)")
                continue
            }
            let record = CalibrationRecord(result: result)
            XCTAssertEqual(record.resonanceBPM, result.resonanceBPM, accuracy: 0.001,
                "CalibrationRecord.resonanceBPM should match ResonanceFrequencyResult.resonanceBPM")
        }
    }

    // MARK: - CalibrationRecord retestAfter is 30 days from creation

    func testCalibrationRecordRetestAfter30Days() {
        guard let result = engine.findResonance(samples: allSamples(plantedBPM: 6.0)) else {
            return XCTFail("No result")
        }
        let now = Date()
        let record = CalibrationRecord(result: result, createdAt: now)
        let expectedRetest = now.addingTimeInterval(30 * 24 * 3600)
        XCTAssertEqual(record.retestAfter.timeIntervalSince1970,
                       expectedRetest.timeIntervalSince1970, accuracy: 1.0)
    }

    func testCalibrationRecordNeedsRetestFalseWhenFresh() {
        guard let result = engine.findResonance(samples: allSamples(plantedBPM: 6.0)) else {
            return XCTFail("No result")
        }
        let record = CalibrationRecord(result: result, createdAt: Date())
        XCTAssertFalse(record.needsRetest)
    }

    func testCalibrationRecordNeedsRetestTrueWhenExpired() {
        guard let result = engine.findResonance(samples: allSamples(plantedBPM: 6.0)) else {
            return XCTFail("No result")
        }
        let thirtyOneDaysAgo = Date().addingTimeInterval(-31 * 24 * 3600)
        let record = CalibrationRecord(result: result, createdAt: thirtyOneDaysAgo)
        XCTAssertTrue(record.needsRetest)
    }

    // MARK: - Candidate BPM count matches runner expectation

    func testCandidateCountIsSix() {
        XCTAssertEqual(CalibrationEngine.candidateBPMs.count, 6)
    }

    func testCandidateBPMRange() {
        let bpms = CalibrationEngine.candidateBPMs
        XCTAssertEqual(bpms.min()!, 4.5, accuracy: 0.001)
        XCTAssertEqual(bpms.max()!, 7.0, accuracy: 0.001)
    }
}
