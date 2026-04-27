import XCTest
@testable import AmachBreatheShared

/// Verifies that reflection rating (1–5) persists correctly into BreathingSessionRecord
/// and survives a Codable round-trip (which mirrors the Storj upload path).
final class ReflectionRatingTests: XCTestCase {

    func testRatingsOneToFivePersist() throws {
        for rating in 1...5 {
            let record = makeRecord(reflectionRating: rating)
            XCTAssertEqual(record.reflectionRating, rating)

            let roundTripped = try roundTrip(record)
            XCTAssertEqual(roundTripped.reflectionRating, rating,
                           "Rating \(rating) lost after JSON round-trip")
        }
    }

    func testNilRatingPersists() throws {
        let record = makeRecord(reflectionRating: nil)
        XCTAssertNil(record.reflectionRating)

        let roundTripped = try roundTrip(record)
        XCTAssertNil(roundTripped.reflectionRating)
    }

    func testRecordIsCompleteWithRating() {
        let record = makeRecord(reflectionRating: 4)
        XCTAssertEqual(record.id, "test-id")
        XCTAssertEqual(record.bpm, 5.5)
        XCTAssertEqual(record.ratio, "4:6")
        XCTAssertEqual(record.coherenceScore, 0.72, accuracy: 0.001)
        XCTAssertEqual(record.reflectionRating, 4)
    }

    func testRecordIsCompleteWithoutRating() {
        let record = makeRecord(reflectionRating: nil)
        XCTAssertNil(record.reflectionRating)
        XCTAssertEqual(record.coherenceScore, 0.72, accuracy: 0.001)
    }

    // MARK: - Helpers

    private func makeRecord(reflectionRating: Int?) -> BreathingSessionRecord {
        BreathingSessionRecord(
            id: "test-id",
            timestamp: Date(timeIntervalSince1970: 1_000_000),
            durationSeconds: 300,
            bpm: 5.5,
            ratio: BreathRatio.fourToSix.rawValue,
            baselineHRV: 38.0,
            recoveryHRV: 52.0,
            avgHRV: 45.0,
            coherenceScore: 0.72,
            reflectionRating: reflectionRating
        )
    }

    private func roundTrip(_ record: BreathingSessionRecord) throws -> BreathingSessionRecord {
        let data = try JSONEncoder().encode(record)
        return try JSONDecoder().decode(BreathingSessionRecord.self, from: data)
    }
}
