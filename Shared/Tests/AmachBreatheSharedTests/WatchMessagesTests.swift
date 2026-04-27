import XCTest
@testable import AmachBreatheShared

final class WatchMessagesTests: XCTestCase {

    func testMakeAndDecodeSessionComplete() throws {
        let record = BreathingSessionRecord(
            id: "abc-123",
            timestamp: Date(timeIntervalSince1970: 1_000_000),
            durationSeconds: 300,
            bpm: 5.5,
            ratio: "4:6",
            baselineHRV: 42.0,
            recoveryHRV: 55.0,
            avgHRV: 48.5,
            coherenceScore: 0.72,
            reflectionRating: 4
        )
        let message = try makeWatchMessage(type: .sessionComplete, payload: record)
        XCTAssertEqual(message[WatchMessageKey.type.rawValue] as? String, WatchMessageType.sessionComplete.rawValue)

        let decoded = try decodeWatchPayload(BreathingSessionRecord.self, from: message)
        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.bpm, record.bpm)
        XCTAssertEqual(decoded.coherenceScore, record.coherenceScore)
        XCTAssertEqual(decoded.reflectionRating, 4)
    }

    func testMakeAndDecodeStartCommand() throws {
        let cmd = StartSessionCommand(bpm: 6.0, durationSeconds: 600)
        let message = try makeWatchMessage(type: .startSession, payload: cmd)

        let decoded = try decodeWatchPayload(StartSessionCommand.self, from: message)
        XCTAssertEqual(decoded.bpm, 6.0)
        XCTAssertEqual(decoded.durationSeconds, 600)
    }

    func testWatchMessageType_extracted() throws {
        let cmd = StartSessionCommand(bpm: 5.0, durationSeconds: 300)
        let message = try makeWatchMessage(type: .startSession, payload: cmd)
        XCTAssertEqual(watchMessageType(from: message), .startSession)
    }

    func testMissingPayload_throws() {
        let message: [String: Any] = [WatchMessageKey.type.rawValue: "sessionComplete"]
        XCTAssertThrowsError(try decodeWatchPayload(BreathingSessionRecord.self, from: message))
    }

    func testResonanceFrequencyResult_codable() throws {
        let result = ResonanceFrequencyResult(
            resonanceBPM: 5.5,
            scores: [4.5: 0.3, 5.0: 0.55, 5.5: 0.78, 6.0: 0.6, 6.5: 0.45, 7.0: 0.35]
        )
        let message = try makeWatchMessage(type: .calibrationResult, payload: result)
        let decoded = try decodeWatchPayload(ResonanceFrequencyResult.self, from: message)
        XCTAssertEqual(decoded.resonanceBPM, 5.5)
        XCTAssertEqual(decoded.scores[5.5] ?? 0, 0.78, accuracy: 0.001)
    }
}
