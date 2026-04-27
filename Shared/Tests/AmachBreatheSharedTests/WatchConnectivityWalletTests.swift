import XCTest
@testable import AmachBreatheShared

/// Tests WCSession message round-trips for wallet state propagation.
final class WatchConnectivityWalletTests: XCTestCase {

    // MARK: - WalletStateMessage Codable

    func testWalletStateMessageConnected() throws {
        let msg = WalletStateMessage(isConnected: true, walletAddress: "0xabc123")
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(WalletStateMessage.self, from: data)
        XCTAssertTrue(decoded.isConnected)
        XCTAssertEqual(decoded.walletAddress, "0xabc123")
    }

    func testWalletStateMessageDisconnected() throws {
        let msg = WalletStateMessage(isConnected: false, walletAddress: nil)
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(WalletStateMessage.self, from: data)
        XCTAssertFalse(decoded.isConnected)
        XCTAssertNil(decoded.walletAddress)
    }

    // MARK: - makeWatchMessage / decodeWatchPayload round-trip

    func testWalletStateMessageWatchEnvelope() throws {
        let msg = WalletStateMessage(isConnected: true, walletAddress: "0xdeadbeef")
        let envelope = try makeWatchMessage(type: .walletState, payload: msg)

        XCTAssertEqual(envelope[WatchMessageKey.type.rawValue] as? String, "walletState")
        XCTAssertNotNil(envelope[WatchMessageKey.payload.rawValue])

        let decoded = try decodeWatchPayload(WalletStateMessage.self, from: envelope)
        XCTAssertTrue(decoded.isConnected)
        XCTAssertEqual(decoded.walletAddress, "0xdeadbeef")
    }

    func testWalletStateRequestMessageType() {
        let envelope = makeWatchMessage(type: .walletStateRequest)
        XCTAssertEqual(envelope[WatchMessageKey.type.rawValue] as? String, "walletStateRequest")
        XCTAssertNil(envelope[WatchMessageKey.payload.rawValue], "walletStateRequest has no payload")
    }

    // MARK: - watchMessageType extraction

    func testWatchMessageTypeWalletState() {
        let envelope: [String: Any] = [WatchMessageKey.type.rawValue: "walletState"]
        XCTAssertEqual(watchMessageType(from: envelope), .walletState)
    }

    func testWatchMessageTypeWalletStateRequest() {
        let envelope: [String: Any] = [WatchMessageKey.type.rawValue: "walletStateRequest"]
        XCTAssertEqual(watchMessageType(from: envelope), .walletStateRequest)
    }

    func testWatchMessageTypeUnknown() {
        let envelope: [String: Any] = [WatchMessageKey.type.rawValue: "unknownType"]
        XCTAssertNil(watchMessageType(from: envelope))
    }

    // MARK: - Session complete message unchanged

    func testSessionCompleteEnvelopeShape() throws {
        let record = BreathingSessionRecord(
            id: "abc", timestamp: Date(), durationSeconds: 300,
            bpm: 6.0, ratio: "4:6",
            baselineHRV: 50, recoveryHRV: 55, avgHRV: 52,
            coherenceScore: 0.8, reflectionRating: nil)
        let envelope = try makeWatchMessage(type: .sessionComplete, payload: record)
        XCTAssertEqual(envelope[WatchMessageKey.type.rawValue] as? String, "sessionComplete")

        let decoded = try decodeWatchPayload(BreathingSessionRecord.self, from: envelope)
        XCTAssertEqual(decoded.id, "abc")
        XCTAssertEqual(decoded.bpm, 6.0, accuracy: 0.001)
    }

    // MARK: - Calibration result message

    func testCalibrationResultEnvelope() throws {
        let result = ResonanceFrequencyResult(resonanceBPM: 5.5, scores: [5.5: 1.0, 6.0: 0.7])
        let envelope = try makeWatchMessage(type: .calibrationResult, payload: result)
        XCTAssertEqual(envelope[WatchMessageKey.type.rawValue] as? String, "calibrationResult")

        let decoded = try decodeWatchPayload(ResonanceFrequencyResult.self, from: envelope)
        XCTAssertEqual(decoded.resonanceBPM, 5.5, accuracy: 0.001)
        XCTAssertEqual(decoded.scores[5.5] ?? 0, 1.0, accuracy: 0.001)
    }

    // MARK: - No-payload message helper

    func testMakeWatchMessageNoPayload() {
        let msg = makeWatchMessage(type: .cancelSession)
        XCTAssertEqual(msg[WatchMessageKey.type.rawValue] as? String, "cancelSession")
        XCTAssertNil(msg[WatchMessageKey.payload.rawValue])
    }

    // MARK: - Missing payload throws

    func testMissingPayloadThrows() {
        let envelope: [String: Any] = [WatchMessageKey.type.rawValue: "sessionComplete"]
        XCTAssertThrowsError(try decodeWatchPayload(BreathingSessionRecord.self, from: envelope))
    }
}
