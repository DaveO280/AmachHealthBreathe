import XCTest
@testable import AmachBreatheShared

/// Tests the full session encode → Storj request → decode round-trip.
/// Local (mock) tests always run.
/// Real-server tests run only when AMACH_API_URL_TEST is set in the environment.
final class StorjIntegrationTests: XCTestCase {

    // MARK: - Round-trip: encode session → Storj request → extract and decode

    func testSessionRoundTripThroughStorjRequest() throws {
        let original = BreathingSessionRecord(
            id: "rt-test-001",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 600,
            bpm: 5.5,
            ratio: "4:6",
            baselineHRV: 48.0,
            recoveryHRV: 62.0,
            avgHRV: 55.0,
            coherenceScore: 0.82,
            reflectionRating: 5
        )
        let key = WalletEncryptionKey(
            walletAddress: "0xtest000000000000000000000000000000test00",
            encryptionKey: String(repeating: "a", count: 64),
            signature: "0x" + String(repeating: "ff", count: 65),
            timestamp: 1_700_000_000_000
        )

        // Encode through StorjRequest (same encoding path as AmachAPIClient.storeBreathingSession)
        let storjReq = StorjRequest(
            action: "storage/store",
            userAddress: key.walletAddress,
            encryptionKey: key,
            data: AnyCodable(original),
            dataType: "breathing-session",
            options: StorjStoreOptions(metadata: ["sessionId": original.id])
        )
        let requestData = try JSONEncoder().encode(storjReq)

        // Extract the `data` field and decode it back as BreathingSessionRecord
        let requestJSON = try JSONSerialization.jsonObject(with: requestData) as! [String: Any]
        let dataField = requestJSON["data"] as! [String: Any]
        let dataBytes = try JSONSerialization.data(withJSONObject: dataField)
        let decoded = try JSONDecoder().decode(BreathingSessionRecord.self, from: dataBytes)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.durationSeconds, original.durationSeconds)
        XCTAssertEqual(decoded.bpm, original.bpm, accuracy: 0.001)
        XCTAssertEqual(decoded.ratio, original.ratio)
        XCTAssertEqual(decoded.baselineHRV, original.baselineHRV, accuracy: 0.001)
        XCTAssertEqual(decoded.recoveryHRV, original.recoveryHRV, accuracy: 0.001)
        XCTAssertEqual(decoded.avgHRV, original.avgHRV, accuracy: 0.001)
        XCTAssertEqual(decoded.coherenceScore, original.coherenceScore, accuracy: 0.001)
        XCTAssertEqual(decoded.reflectionRating, original.reflectionRating)
        // Timestamp: encoded as ISO8601 string, decoded back — must match to nearest second
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970,
                       original.timestamp.timeIntervalSince1970, accuracy: 1.0)
    }

    // MARK: - BreathingSessionEvent round-trip

    func testBreathingSessionEventRoundTrip() throws {
        let record = BreathingSessionRecord(
            id: "evt-rt-001",
            timestamp: Date(timeIntervalSince1970: 1_700_100_000),
            durationSeconds: 300,
            bpm: 6.0, ratio: "1:1",
            baselineHRV: 50, recoveryHRV: 58, avgHRV: 54,
            coherenceScore: 0.75, reflectionRating: nil)

        let event = BreathingSessionEvent(from: record, platform: "watchos")
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(BreathingSessionEvent.self, from: data)

        XCTAssertEqual(decoded.id, event.id)
        XCTAssertEqual(decoded.eventType, "BREATHING_SESSION")
        XCTAssertEqual(decoded.data["sessionId"], record.id)
        XCTAssertEqual(decoded.metadata.platform, "watchos")
        XCTAssertEqual(decoded.metadata.source, "user")
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970,
                       event.timestamp.timeIntervalSince1970, accuracy: 1.0)
    }

    // MARK: - StorjRetrievedData round-trip

    func testStorjRetrievedDataDecoding() throws {
        let record = BreathingSessionRecord(
            id: "retrieve-001",
            timestamp: Date(timeIntervalSince1970: 1_700_200_000),
            durationSeconds: 900, bpm: 5.0, ratio: "4:6",
            baselineHRV: 45, recoveryHRV: 55, avgHRV: 50,
            coherenceScore: 0.65, reflectionRating: 3)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let recordData = try encoder.encode(record)
        let recordJSON = try JSONSerialization.jsonObject(with: recordData)

        let envelope: [String: Any] = [
            "success": true,
            "result": [
                "data": recordJSON,
                "storjUri": "storj://bucket/breathing/retrieve-001.enc",
                "contentHash": "sha256-mock",
                "verified": true
            ]
        ]
        let envelopeData = try JSONSerialization.data(withJSONObject: envelope)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(
            StorjResponse<StorjRetrievedData<BreathingSessionRecord>>.self,
            from: envelopeData)

        XCTAssertTrue(response.success)
        let retrieved = response.result?.data
        XCTAssertEqual(retrieved?.id, "retrieve-001")
        XCTAssertEqual(retrieved?.bpm ?? 0, 5.0, accuracy: 0.001)
        XCTAssertEqual(retrieved?.reflectionRating, 3)
        XCTAssertEqual(response.result?.storjUri, "storj://bucket/breathing/retrieve-001.enc")
        XCTAssertEqual(response.result?.verified, true)
    }

    // MARK: - Real-server integration test (skipped unless AMACH_API_URL_TEST is set)

    func testRealStorjStoreAndRetrieve() async throws {
        guard let testURL = ProcessInfo.processInfo.environment["AMACH_API_URL_TEST"] else {
            throw XCTSkip("AMACH_API_URL_TEST not set — skipping real server test")
        }
        guard let testAddress = ProcessInfo.processInfo.environment["AMACH_TEST_WALLET_ADDRESS"],
              let testKey = ProcessInfo.processInfo.environment["AMACH_TEST_ENCRYPTION_KEY"]
        else {
            throw XCTSkip("AMACH_TEST_WALLET_ADDRESS / AMACH_TEST_ENCRYPTION_KEY not set")
        }

        let client = AmachAPIClient(baseURL: URL(string: testURL))
        let encKey = WalletEncryptionKey(
            walletAddress: testAddress,
            encryptionKey: testKey,
            signature: "",
            timestamp: Int(Date().timeIntervalSince1970 * 1000)
        )
        let record = BreathingSessionRecord(
            id: "integration-test-\(Int(Date().timeIntervalSince1970))",
            timestamp: Date(),
            durationSeconds: 300,
            bpm: 6.0, ratio: "4:6",
            baselineHRV: 50, recoveryHRV: 58, avgHRV: 54,
            coherenceScore: 0.78, reflectionRating: nil)

        // Store
        let storeResult = try await client.storeBreathingSession(
            record: record, walletAddress: testAddress, encryptionKey: encKey)
        XCTAssertFalse(storeResult.storjUri.isEmpty)
        XCTAssertFalse(storeResult.contentHash.isEmpty)

        // Retrieve
        let retrieved = try await client.retrieveBreathingSession(
            storjUri: storeResult.storjUri,
            walletAddress: testAddress,
            encryptionKey: encKey)
        XCTAssertEqual(retrieved.id, record.id)
        XCTAssertEqual(retrieved.bpm, record.bpm, accuracy: 0.001)
        XCTAssertEqual(retrieved.coherenceScore, record.coherenceScore, accuracy: 0.001)
        XCTAssertEqual(retrieved.durationSeconds, record.durationSeconds)

        // List — should contain the record we just stored
        let items = try await client.listBreathingSessions(
            walletAddress: testAddress, encryptionKey: encKey)
        XCTAssertTrue(items.contains { $0.uri == storeResult.storjUri },
            "List should contain the stored session URI")
    }
}
