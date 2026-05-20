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

    func testStartCommand_companionFieldsRoundTrip() throws {
        let cmd = StartSessionCommand(
            bpm: 5.5,
            durationSeconds: 300,
            ratio: "4:6",
            sessionId: "abc",
            companionAudioEnabled: true
        )
        let message = try makeWatchMessage(type: .startSession, payload: cmd)
        let decoded = try decodeWatchPayload(StartSessionCommand.self, from: message)
        XCTAssertEqual(decoded.sessionId, "abc")
        XCTAssertEqual(decoded.companionAudioEnabled, true)
    }

    func testSessionStartedMessage_roundTrip() throws {
        let started = SessionStartedMessage(
            sessionId: "s1",
            bpm: 5.5,
            durationSeconds: 300,
            ratio: "4:6",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let message = try makeWatchMessage(type: .sessionStarted, payload: started)
        XCTAssertEqual(watchMessageType(from: message), .sessionStarted)
        let decoded = try decodeWatchPayload(SessionStartedMessage.self, from: message)
        XCTAssertEqual(decoded.sessionId, "s1")
        XCTAssertEqual(decoded.bpm, 5.5)
    }

    func testSessionPhaseHint_roundTrip() throws {
        let hint = SessionPhaseHintMessage(sessionId: "s1", phase: .mainStarted)
        let message = try makeWatchMessage(type: .sessionPhaseHint, payload: hint)
        let decoded = try decodeWatchPayload(SessionPhaseHintMessage.self, from: message)
        XCTAssertEqual(decoded.phase, .mainStarted)
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

    func testWatchMessageType_unknownTypeReturnsNil() {
        let message: [String: Any] = [WatchMessageKey.type.rawValue: "not-a-real-type"]
        XCTAssertNil(watchMessageType(from: message))
    }

    func testSessionStartedMessage_rejectsEmptySessionId() throws {
        let started = SessionStartedMessage(
            sessionId: "",
            bpm: 5.5,
            durationSeconds: 300,
            ratio: "4:6"
        )
        let message = try makeWatchMessage(type: .sessionStarted, payload: started)
        let decoded = try decodeWatchPayload(SessionStartedMessage.self, from: message)
        XCTAssertTrue(decoded.sessionId.isEmpty)
    }

    func testSessionPhaseHint_invalidPhaseStringFailsDecode() {
        let message: [String: Any] = [
            WatchMessageKey.type.rawValue: WatchMessageType.sessionPhaseHint.rawValue,
            WatchMessageKey.payload.rawValue: #"{"sessionId":"s1","phase":"bogus"}"#
        ]
        XCTAssertThrowsError(try decodeWatchPayload(SessionPhaseHintMessage.self, from: message))
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
