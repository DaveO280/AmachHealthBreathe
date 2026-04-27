import XCTest
@testable import AmachBreatheShared

/// Integration tests for the WatchConnectivity message layer.
///
/// WCSession itself is HealthKit/WatchKit platform-only (can't run in SPM tests).
/// These tests validate the message serialisation layer — makeWatchMessage /
/// decodeWatchPayload / watchMessageType — under conditions that model real
/// WCSession use: sequential ordering, burst delivery, simulated round-trip
/// latency, and all message types in the session lifecycle.
final class WatchConnectivityIntegrationTests: XCTestCase {

    // MARK: - All message types round-trip

    func testAllMessageTypesRoundTripTypeField() throws {
        let allTypes: [(WatchMessageType, () throws -> [String: Any])] = [
            (.sessionComplete, {
                try makeWatchMessage(type: .sessionComplete, payload: BreathingSessionRecord(
                    id: "t1", timestamp: Date(), durationSeconds: 300,
                    bpm: 5.5, ratio: "4:6",
                    baselineHRV: 50, recoveryHRV: 58, avgHRV: 54,
                    coherenceScore: 0.8, reflectionRating: nil))
            }),
            (.startSession, {
                try makeWatchMessage(type: .startSession,
                    payload: StartSessionCommand(bpm: 5.5, durationSeconds: 300))
            }),
            (.calibrationResult, {
                try makeWatchMessage(type: .calibrationResult,
                    payload: ResonanceFrequencyResult(resonanceBPM: 5.5,
                        scores: [5.0: 0.7, 5.5: 0.9, 6.0: 0.65]))
            }),
            (.walletState, {
                try makeWatchMessage(type: .walletState,
                    payload: WalletStateMessage(isConnected: true, walletAddress: "0xabc"))
            }),
            (.cancelSession, { [WatchMessageKey.type.rawValue: WatchMessageType.cancelSession.rawValue] }),
            (.walletStateRequest, { makeWatchMessage(type: .walletStateRequest) }),
        ]

        for (expectedType, factory) in allTypes {
            let envelope = try factory()
            let decoded = watchMessageType(from: envelope)
            XCTAssertEqual(decoded, expectedType,
                "Type field round-trip failed for '\(expectedType.rawValue)'")
        }
    }

    // MARK: - Sequential ordering under simulated latency

    func testFIFOOrderingPreservedUnderSimulatedLatency() async throws {
        // Models WCSession FIFO delivery: 20 start commands sent in order,
        // each with 5 ms simulated transit delay. Ordering must be preserved.
        let count = 20
        var sent: [Int] = []
        var received: [Int] = []

        for i in 0..<count {
            let cmd = StartSessionCommand(bpm: Double(i), durationSeconds: 300 + i)
            let msg = try makeWatchMessage(type: .startSession, payload: cmd)
            sent.append(i)

            // Simulate per-message transit delay (5 ms)
            try await Task.sleep(nanoseconds: 5_000_000)

            let decoded = try decodeWatchPayload(StartSessionCommand.self, from: msg)
            received.append(Int(decoded.bpm))
        }

        XCTAssertEqual(sent, received, "FIFO ordering must survive simulated per-message latency")
    }

    func testRoundTripUnderSimulatedLatency_100ms() async throws {
        let record = BreathingSessionRecord(
            id: "latency-100ms", timestamp: Date(), durationSeconds: 600,
            bpm: 6.0, ratio: "4:6",
            baselineHRV: 45, recoveryHRV: 62, avgHRV: 53,
            coherenceScore: 0.79, reflectionRating: 4)

        let envelope = try makeWatchMessage(type: .sessionComplete, payload: record)

        // Simulate 100 ms Watch ↔ iPhone transit
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(watchMessageType(from: envelope), .sessionComplete)
        let decoded = try decodeWatchPayload(BreathingSessionRecord.self, from: envelope)

        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.bpm, record.bpm, accuracy: 0.001)
        XCTAssertEqual(decoded.coherenceScore, record.coherenceScore, accuracy: 0.001)
        XCTAssertEqual(decoded.reflectionRating, 4)
    }

    // MARK: - High-volume burst (models Bluetooth reconnect replay)

    func testHighVolumeBurst_200Messages() throws {
        let count = 200
        var successCount = 0
        let start = CFAbsoluteTimeGetCurrent()

        for i in 0..<count {
            let bpm = 5.0 + Double(i % 10) * 0.1
            let cmd = StartSessionCommand(bpm: bpm, durationSeconds: 300)
            let msg = try makeWatchMessage(type: .startSession, payload: cmd)
            let decoded = try decodeWatchPayload(StartSessionCommand.self, from: msg)
            if abs(decoded.bpm - bpm) < 0.001 { successCount += 1 }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertEqual(successCount, count, "All \(count) messages must decode correctly")
        XCTAssertLessThan(elapsed, 1.0, "200-message burst must complete in < 1 s")
    }

    // MARK: - Full session lifecycle sequence

    func testSessionLifecycleSequence() throws {
        // Step 1: iOS → Watch: start session
        let startCmd = StartSessionCommand(bpm: 5.5, durationSeconds: 300)
        let startMsg = try makeWatchMessage(type: .startSession, payload: startCmd)
        XCTAssertEqual(watchMessageType(from: startMsg), .startSession)
        let decodedStart = try decodeWatchPayload(StartSessionCommand.self, from: startMsg)
        XCTAssertEqual(decodedStart.bpm, 5.5, accuracy: 0.001)
        XCTAssertEqual(decodedStart.durationSeconds, 300)

        // Step 2: Watch → iOS: session complete
        let record = BreathingSessionRecord(
            id: "lifecycle-001", timestamp: Date(), durationSeconds: 300,
            bpm: 5.5, ratio: "4:6",
            baselineHRV: 50, recoveryHRV: 60, avgHRV: 55,
            coherenceScore: 0.72, reflectionRating: nil)
        let completeMsg = try makeWatchMessage(type: .sessionComplete, payload: record)
        XCTAssertEqual(watchMessageType(from: completeMsg), .sessionComplete)
        let decodedRecord = try decodeWatchPayload(BreathingSessionRecord.self, from: completeMsg)
        XCTAssertEqual(decodedRecord.id, "lifecycle-001")
        XCTAssertEqual(decodedRecord.coherenceScore, 0.72, accuracy: 0.001)

        // Step 3: Watch → iOS: calibration result
        let calResult = ResonanceFrequencyResult(
            resonanceBPM: 5.5,
            scores: [4.5: 0.4, 5.0: 0.6, 5.5: 0.9, 6.0: 0.7, 6.5: 0.5, 7.0: 0.35])
        let calMsg = try makeWatchMessage(type: .calibrationResult, payload: calResult)
        XCTAssertEqual(watchMessageType(from: calMsg), .calibrationResult)
        let decodedCal = try decodeWatchPayload(ResonanceFrequencyResult.self, from: calMsg)
        XCTAssertEqual(decodedCal.resonanceBPM, 5.5, accuracy: 0.001)
        XCTAssertEqual(decodedCal.scores[5.5] ?? 0, 0.9, accuracy: 0.001)

        // Step 4: iOS → Watch: wallet state request (no payload)
        let walletReqMsg = makeWatchMessage(type: .walletStateRequest)
        XCTAssertEqual(watchMessageType(from: walletReqMsg), .walletStateRequest)
        XCTAssertNil(walletReqMsg[WatchMessageKey.payload.rawValue])

        // Step 5: Watch → iOS: wallet state response
        let walletMsg = try makeWatchMessage(type: .walletState,
            payload: WalletStateMessage(isConnected: true, walletAddress: "0xdeadbeef"))
        let decodedWallet = try decodeWatchPayload(WalletStateMessage.self, from: walletMsg)
        XCTAssertTrue(decodedWallet.isConnected)
        XCTAssertEqual(decodedWallet.walletAddress, "0xdeadbeef")

        // Step 6: iOS → Watch: cancel session (no payload)
        let cancelMsg = makeWatchMessage(type: .cancelSession)
        XCTAssertEqual(watchMessageType(from: cancelMsg), .cancelSession)
    }

    // MARK: - Wallet state propagation sequence

    func testWalletConnectThenDisconnect() throws {
        let connected = try makeWatchMessage(type: .walletState,
            payload: WalletStateMessage(isConnected: true, walletAddress: "0x1234"))
        let disconnected = try makeWatchMessage(type: .walletState,
            payload: WalletStateMessage(isConnected: false, walletAddress: nil))

        let d1 = try decodeWatchPayload(WalletStateMessage.self, from: connected)
        let d2 = try decodeWatchPayload(WalletStateMessage.self, from: disconnected)

        XCTAssertTrue(d1.isConnected)
        XCTAssertEqual(d1.walletAddress, "0x1234")
        XCTAssertFalse(d2.isConnected)
        XCTAssertNil(d2.walletAddress)
    }

    // MARK: - Malformed input handling

    func testMissingTypeField_returnsNil() {
        let envelope: [String: Any] = [WatchMessageKey.payload.rawValue: Data()]
        XCTAssertNil(watchMessageType(from: envelope))
    }

    func testEmptyEnvelope_returnsNilType() {
        XCTAssertNil(watchMessageType(from: [:]))
    }

    func testUnknownMessageType_returnsNil() {
        let envelope: [String: Any] = [WatchMessageKey.type.rawValue: "futureV2MessageType"]
        XCTAssertNil(watchMessageType(from: envelope))
    }

    func testMissingPayload_throws() {
        let envelope: [String: Any] = [WatchMessageKey.type.rawValue: "sessionComplete"]
        XCTAssertThrowsError(
            try decodeWatchPayload(BreathingSessionRecord.self, from: envelope),
            "Missing payload must throw")
    }

    func testWrongPayloadType_throws() {
        struct Alien: Codable { let x: Int }
        let envelope: [String: Any] = [
            WatchMessageKey.type.rawValue: "sessionComplete",
            WatchMessageKey.payload.rawValue: try! JSONSerialization.data(withJSONObject: ["x": 42])
        ]
        XCTAssertThrowsError(
            try decodeWatchPayload(BreathingSessionRecord.self, from: envelope),
            "Mismatched payload type must throw")
    }

    // MARK: - Data integrity: all BreathingSessionRecord fields survive round-trip

    func testSessionRecordFullFieldFidelity() throws {
        let original = BreathingSessionRecord(
            id: "full-fidelity-test",
            timestamp: Date(timeIntervalSince1970: 1_750_000_000),
            durationSeconds: 900,
            bpm: 5.5,
            ratio: "4:6",
            baselineHRV: 42.7,
            recoveryHRV: 61.3,
            avgHRV: 52.1,
            coherenceScore: 0.847,
            reflectionRating: 5)

        let envelope = try makeWatchMessage(type: .sessionComplete, payload: original)
        let decoded = try decodeWatchPayload(BreathingSessionRecord.self, from: envelope)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.durationSeconds, original.durationSeconds)
        XCTAssertEqual(decoded.bpm, original.bpm, accuracy: 0.001)
        XCTAssertEqual(decoded.ratio, original.ratio)
        XCTAssertEqual(decoded.baselineHRV, original.baselineHRV, accuracy: 0.001)
        XCTAssertEqual(decoded.recoveryHRV, original.recoveryHRV, accuracy: 0.001)
        XCTAssertEqual(decoded.avgHRV, original.avgHRV, accuracy: 0.001)
        XCTAssertEqual(decoded.coherenceScore, original.coherenceScore, accuracy: 0.001)
        XCTAssertEqual(decoded.reflectionRating, 5)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970,
            original.timestamp.timeIntervalSince1970, accuracy: 1.0)
    }
}
