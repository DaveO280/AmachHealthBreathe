import XCTest
@testable import AmachBreatheShared

final class SessionHistoryModelTests: XCTestCase {

    private func makeRecord(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        durationSeconds: Int = 300,
        bpm: Double = 6.0,
        ratio: String = "4:6",
        avgHRV: Double = 55.0,
        coherenceScore: Double = 0.75,
        reflectionRating: Int? = nil
    ) -> BreathingSessionRecord {
        BreathingSessionRecord(
            id: id,
            timestamp: timestamp,
            durationSeconds: durationSeconds,
            bpm: bpm,
            ratio: ratio,
            baselineHRV: avgHRV,
            recoveryHRV: avgHRV + 5,
            avgHRV: avgHRV,
            coherenceScore: coherenceScore,
            reflectionRating: reflectionRating
        )
    }

    // MARK: - Sorting

    func testRowsSortedNewestFirst() {
        let now = Date()
        let older = makeRecord(id: "old", timestamp: now.addingTimeInterval(-86400))
        let newer = makeRecord(id: "new", timestamp: now)
        let rows = SessionHistoryModel.rows(from: [older, newer])
        XCTAssertEqual(rows.first?.id, "new")
        XCTAssertEqual(rows.last?.id, "old")
    }

    // MARK: - Filtering

    func testZeroDurationFiltered() {
        let valid = makeRecord(durationSeconds: 300)
        let zero  = makeRecord(durationSeconds: 0)
        let rows  = SessionHistoryModel.rows(from: [valid, zero])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].durationMinutes, 5)
    }

    func testOnlyZeroDurationReturnsEmpty() {
        let rows = SessionHistoryModel.rows(from: [makeRecord(durationSeconds: 0)])
        XCTAssertTrue(rows.isEmpty)
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertTrue(SessionHistoryModel.rows(from: []).isEmpty)
    }

    // MARK: - Field mapping

    func testFieldsMappedCorrectly() {
        let now = Date()
        let record = makeRecord(
            id: "abc",
            timestamp: now,
            durationSeconds: 450,
            bpm: 5.5,
            ratio: "1:1",
            avgHRV: 62.0,
            coherenceScore: 0.83,
            reflectionRating: 4
        )
        let row = SessionHistoryModel.row(from: record)
        XCTAssertEqual(row.id, "abc")
        XCTAssertEqual(row.bpm, 5.5)
        XCTAssertEqual(row.ratio, "1:1")
        XCTAssertEqual(row.avgHRV, 62.0, accuracy: 0.001)
        XCTAssertEqual(row.coherenceScore, 0.83, accuracy: 0.001)
        XCTAssertEqual(row.reflectionRating, 4)
        XCTAssertEqual(row.durationMinutes, 7)
    }

    // MARK: - durationMinutes

    func testDurationMinutesRoundsDown() {
        // 450s = 7.5 min → 7
        let row = SessionHistoryModel.row(from: makeRecord(durationSeconds: 450))
        XCTAssertEqual(row.durationMinutes, 7)
    }

    func testDurationMinutesMinimumOne() {
        // 30s → max(1, 0) = 1
        let row = SessionHistoryModel.row(from: makeRecord(durationSeconds: 30))
        XCTAssertEqual(row.durationMinutes, 1)
    }

    func testDurationMinutes5min() {
        let row = SessionHistoryModel.row(from: makeRecord(durationSeconds: 300))
        XCTAssertEqual(row.durationMinutes, 5)
    }

    func testDurationMinutes10min() {
        let row = SessionHistoryModel.row(from: makeRecord(durationSeconds: 600))
        XCTAssertEqual(row.durationMinutes, 10)
    }

    func testDurationMinutes15min() {
        let row = SessionHistoryModel.row(from: makeRecord(durationSeconds: 900))
        XCTAssertEqual(row.durationMinutes, 15)
    }

    // MARK: - durationLabel

    func testDurationLabel() {
        let row = SessionHistoryModel.row(from: makeRecord(durationSeconds: 300))
        XCTAssertEqual(row.durationLabel, "5 min")
    }

    // MARK: - coherencePercent

    func testCoherencePercentRounding() {
        let row = SessionHistoryModel.row(from: makeRecord(coherenceScore: 0.756))
        XCTAssertEqual(row.coherencePercent, 76)
    }

    func testCoherencePercentZero() {
        let row = SessionHistoryModel.row(from: makeRecord(coherenceScore: 0.0))
        XCTAssertEqual(row.coherencePercent, 0)
    }

    func testCoherencePercentHundred() {
        let row = SessionHistoryModel.row(from: makeRecord(coherenceScore: 1.0))
        XCTAssertEqual(row.coherencePercent, 100)
    }

    // MARK: - dateLabel

    func testDateLabelFormat() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        // April 27 2026 UTC
        let comps = DateComponents(
            calendar: cal, timeZone: TimeZone(identifier: "UTC"),
            year: 2026, month: 4, day: 27, hour: 12)
        let date = cal.date(from: comps)!
        let row = SessionHistoryModel.row(from: makeRecord(timestamp: date))
        // "Apr 27" — locale-independent if using fixed format
        XCTAssertTrue(row.dateLabel.contains("27"), "Expected day 27 in label: \(row.dateLabel)")
    }

    // MARK: - reflectionRating nil

    func testReflectionRatingNil() {
        let row = SessionHistoryModel.row(from: makeRecord(reflectionRating: nil))
        XCTAssertNil(row.reflectionRating)
    }

    func testReflectionRatingPresent() {
        let row = SessionHistoryModel.row(from: makeRecord(reflectionRating: 3))
        XCTAssertEqual(row.reflectionRating, 3)
    }
}
