import XCTest
@testable import AmachBreatheShared

/// Verifies that Storj request payloads have the exact field names and structure
/// expected by the /api/storj endpoint. Any field name change here breaks the backend.
final class StorjPayloadTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func makeKey() -> WalletEncryptionKey {
        WalletEncryptionKey(
            walletAddress: "0xabc123def456abc123def456abc123def456abc1",
            encryptionKey: String(repeating: "a", count: 64),
            signature: "0x" + String(repeating: "ff", count: 65),
            timestamp: 1_700_000_000_000
        )
    }

    private func makeRecord() -> BreathingSessionRecord {
        BreathingSessionRecord(
            id: "test-session-001",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 300,
            bpm: 6.0,
            ratio: "4:6",
            baselineHRV: 52.0,
            recoveryHRV: 60.0,
            avgHRV: 56.0,
            coherenceScore: 0.78,
            reflectionRating: 4
        )
    }

    // MARK: - WalletEncryptionKey wire format

    func testWalletKeyEncodesWithWebFieldNames() throws {
        let key = makeKey()
        let data = try encoder.encode(key)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Web-side expects: walletAddress, key (not encryptionKey), signature, derivedAt (not timestamp)
        XCTAssertNotNil(json["walletAddress"], "Missing walletAddress")
        XCTAssertNotNil(json["key"],           "Missing 'key' (web field for encryptionKey)")
        XCTAssertNotNil(json["signature"],     "Missing signature")
        XCTAssertNotNil(json["derivedAt"],     "Missing 'derivedAt' (web field for timestamp)")
        XCTAssertNil(json["encryptionKey"],    "Should NOT encode as 'encryptionKey' — web expects 'key'")
        XCTAssertNil(json["timestamp"],        "Should NOT encode as 'timestamp' — web expects 'derivedAt'")
    }

    func testWalletKeyRoundTrip() throws {
        let key = makeKey()
        let data = try encoder.encode(key)
        let decoded = try decoder.decode(WalletEncryptionKey.self, from: data)

        XCTAssertEqual(decoded.walletAddress, key.walletAddress)
        XCTAssertEqual(decoded.encryptionKey, key.encryptionKey)
        XCTAssertEqual(decoded.signature, key.signature)
        XCTAssertEqual(decoded.timestamp, key.timestamp)
    }

    func testWalletKeyDecodesLegacyFields() throws {
        // Backend may return 'encryptionKey' and 'timestamp' instead of 'key' and 'derivedAt'
        let legacyJSON = """
        {
            "walletAddress": "0xabc",
            "encryptionKey": "abcdef",
            "signature": "0xsig",
            "timestamp": 1700000000000
        }
        """.data(using: .utf8)!
        let decoded = try decoder.decode(WalletEncryptionKey.self, from: legacyJSON)
        XCTAssertEqual(decoded.encryptionKey, "abcdef")
        XCTAssertEqual(decoded.timestamp, 1_700_000_000_000)
    }

    // MARK: - StorjRequest shape

    func testStorjRequestStoreShape() throws {
        let record = makeRecord()
        let key = makeKey()
        let request = StorjRequest(
            action: "storage/store",
            userAddress: key.walletAddress,
            encryptionKey: key,
            data: AnyCodable(record),
            dataType: "breathing-session",
            options: StorjStoreOptions(metadata: ["sessionId": record.id])
        )
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["action"] as? String, "storage/store")
        XCTAssertEqual(json["userAddress"] as? String, key.walletAddress)
        XCTAssertEqual(json["dataType"] as? String, "breathing-session")
        XCTAssertNotNil(json["encryptionKey"])
        XCTAssertNotNil(json["data"])
        XCTAssertNotNil(json["options"])
    }

    func testStorjListRequestShape() throws {
        let key = makeKey()
        let request = StorjListRequest(
            action: "storage/list",
            userAddress: key.walletAddress,
            encryptionKey: key,
            dataType: "breathing-session"
        )
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["action"] as? String, "storage/list")
        XCTAssertEqual(json["dataType"] as? String, "breathing-session")
    }

    func testStorjRetrieveRequestShape() throws {
        let key = makeKey()
        let request = StorjRetrieveRequest(
            action: "storage/retrieve",
            userAddress: key.walletAddress,
            encryptionKey: key,
            storjUri: "storj://bucket/path/file.enc"
        )
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["action"] as? String, "storage/retrieve")
        XCTAssertEqual(json["storjUri"] as? String, "storj://bucket/path/file.enc")
    }

    // MARK: - BreathingSessionRecord shape

    func testSessionRecordRoundTrip() throws {
        let record = makeRecord()
        let data = try encoder.encode(record)
        let decoded = try decoder.decode(BreathingSessionRecord.self, from: data)

        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.durationSeconds, record.durationSeconds)
        XCTAssertEqual(decoded.bpm, record.bpm, accuracy: 0.001)
        XCTAssertEqual(decoded.ratio, record.ratio)
        XCTAssertEqual(decoded.baselineHRV, record.baselineHRV, accuracy: 0.001)
        XCTAssertEqual(decoded.recoveryHRV, record.recoveryHRV, accuracy: 0.001)
        XCTAssertEqual(decoded.avgHRV, record.avgHRV, accuracy: 0.001)
        XCTAssertEqual(decoded.coherenceScore, record.coherenceScore, accuracy: 0.001)
        XCTAssertEqual(decoded.reflectionRating, record.reflectionRating)
    }

    // MARK: - BreathingSessionEvent shape

    func testBreathingSessionEventShape() throws {
        let record = makeRecord()
        let event = BreathingSessionEvent(from: record, platform: "watchos")
        let data = try encoder.encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["eventType"] as? String, "BREATHING_SESSION")
        XCTAssertNotNil(json["id"])
        XCTAssertNotNil(json["timestamp"])
        XCTAssertNotNil(json["metadata"])

        let eventData = json["data"] as? [String: String]
        XCTAssertNotNil(eventData, "data field must be [String: String]")
        XCTAssertEqual(eventData?["sessionId"], record.id)
        XCTAssertEqual(eventData?["bpm"], String(record.bpm))
        XCTAssertNotNil(eventData?["coherenceScore"])
        XCTAssertNotNil(eventData?["avgHRV"])

        let meta = json["metadata"] as? [String: String]
        XCTAssertEqual(meta?["platform"], "watchos")
        XCTAssertEqual(meta?["version"], "1")
        XCTAssertEqual(meta?["source"], "user")
    }

    func testBreathingSessionEventDefaultPlatformIsIOS() {
        let event = BreathingSessionEvent(from: makeRecord())
        XCTAssertEqual(event.metadata.platform, "ios")
    }

    // MARK: - StorjResponse decoding

    func testStorjResponseSuccessDecoding() throws {
        let json = """
        {
            "success": true,
            "result": {
                "storjUri": "storj://bucket/breathing/session.enc",
                "contentHash": "sha256-abc123",
                "size": 1024
            }
        }
        """.data(using: .utf8)!
        let response = try decoder.decode(StorjResponse<StorjStoreResult>.self, from: json)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.result?.storjUri, "storj://bucket/breathing/session.enc")
        XCTAssertEqual(response.result?.contentHash, "sha256-abc123")
        XCTAssertEqual(response.result?.size, 1024)
    }

    func testStorjResponseErrorDecoding() throws {
        let json = """
        { "success": false, "error": "Unauthorized" }
        """.data(using: .utf8)!
        let response = try decoder.decode(StorjResponse<StorjStoreResult>.self, from: json)
        XCTAssertFalse(response.success)
        XCTAssertEqual(response.error, "Unauthorized")
        XCTAssertNil(response.result)
        XCTAssertThrowsError(try response.unwrapped())
    }

    func testStorjListItemDecoding() throws {
        let json = """
        [{
            "uri": "storj://bucket/breathing/abc.enc",
            "contentHash": "sha256-xyz",
            "size": 512,
            "uploadedAt": 1700000000000,
            "dataType": "breathing-session",
            "metadata": { "sessionId": "abc", "bpm": "6.0" }
        }]
        """.data(using: .utf8)!
        let items = try decoder.decode([StorjListItem].self, from: json)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].uri, "storj://bucket/breathing/abc.enc")
        XCTAssertEqual(items[0].dataType, "breathing-session")
        XCTAssertEqual(items[0].metadata?["sessionId"], "abc")
    }
}
