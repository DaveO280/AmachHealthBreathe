// APIClientTests.swift — Phase 0: API client compiles, mocked round-trips work

import XCTest
@testable import AmachBreatheShared

final class APIClientTests: XCTestCase {

    // MARK: - WalletEncryptionKey encoding round-trip

    func testWalletEncryptionKeyEncodesForWeb() throws {
        let key = WalletEncryptionKey(
            walletAddress: "0xabc123",
            encryptionKey: "deadbeef",
            signature: "0xsig",
            timestamp: 1_700_000_000_000
        )

        let data = try JSONEncoder().encode(key)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Web expects "key" not "encryptionKey", "derivedAt" not "timestamp"
        XCTAssertEqual(json["key"] as? String, "deadbeef")
        XCTAssertEqual(json["derivedAt"] as? Int, 1_700_000_000_000)
        XCTAssertEqual(json["walletAddress"] as? String, "0xabc123")
        XCTAssertNil(json["encryptionKey"], "Should not emit encryptionKey — web expects 'key'")
    }

    func testWalletEncryptionKeyDecodesWebFormat() throws {
        let json: [String: Any] = [
            "walletAddress": "0xdef456",
            "key": "cafebabe",
            "signature": "0xsig2",
            "derivedAt": 1_700_000_001_000
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let key = try JSONDecoder().decode(WalletEncryptionKey.self, from: data)

        XCTAssertEqual(key.walletAddress, "0xdef456")
        XCTAssertEqual(key.encryptionKey, "cafebabe")
        XCTAssertEqual(key.timestamp, 1_700_000_001_000)
    }

    func testWalletEncryptionKeyDecodesLegacyFormat() throws {
        // Older payloads used "encryptionKey" and "timestamp"
        let json: [String: Any] = [
            "walletAddress": "0x999",
            "encryptionKey": "legacykey",
            "timestamp": 1_600_000_000_000
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let key = try JSONDecoder().decode(WalletEncryptionKey.self, from: data)
        XCTAssertEqual(key.encryptionKey, "legacykey")
    }

    // MARK: - BreathingSessionRecord encoding

    func testBreathingSessionRecordRoundTrip() throws {
        let session = BreathingSessionRecord(
            id: "test-session-1",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 600,
            bpm: 5.5,
            ratio: "1:1",
            baselineHRV: 42.0,
            recoveryHRV: 55.0,
            avgHRV: 48.5,
            coherenceScore: 0.78,
            reflectionRating: 4
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BreathingSessionRecord.self, from: data)

        XCTAssertEqual(decoded.id, "test-session-1")
        XCTAssertEqual(decoded.durationSeconds, 600)
        XCTAssertEqual(decoded.bpm, 5.5, accuracy: 0.001)
        XCTAssertEqual(decoded.ratio, "1:1")
        XCTAssertEqual(decoded.coherenceScore, 0.78, accuracy: 0.001)
        XCTAssertEqual(decoded.reflectionRating, 4)
    }

    func testBreathingSessionRecordNilReflection() throws {
        let session = BreathingSessionRecord(
            id: "no-rating",
            timestamp: Date(),
            durationSeconds: 300,
            bpm: 6.0,
            ratio: "4:6",
            baselineHRV: 38.0,
            recoveryHRV: 45.0,
            avgHRV: 40.0,
            coherenceScore: 0.65,
            reflectionRating: nil
        )

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(BreathingSessionRecord.self, from: data)
        XCTAssertNil(decoded.reflectionRating)
    }

    // MARK: - StorjStoreResult decoding

    func testStorjStoreResultDecoding() throws {
        let json = """
        {
            "success": true,
            "result": {
                "storjUri": "sj://bucket/path/file.json",
                "contentHash": "abc123",
                "size": 1024
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(StorjResponse<StorjStoreResult>.self, from: json)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.result?.storjUri, "sj://bucket/path/file.json")
        XCTAssertEqual(response.result?.contentHash, "abc123")
    }

    func testStorjResponseUnwrapFailureThrows() {
        let response = StorjResponse<StorjStoreResult>(success: false, result: nil, error: "Not found")
        XCTAssertThrowsError(try response.unwrapped())
    }

    func testStorjResponseUnwrapSucceeds() throws {
        let result = StorjStoreResult(storjUri: "sj://x", contentHash: "abc", size: 100)
        let response = StorjResponse(success: true, result: result, error: nil)
        let unwrapped = try response.unwrapped()
        XCTAssertEqual(unwrapped.storjUri, "sj://x")
    }

    // MARK: - AmachAPIClient init

    func testAPIClientInitWithCustomURL() {
        let client = AmachAPIClient(baseURL: URL(string: "https://test.amachhealth.com"))
        XCTAssertNotNil(client)
    }

    func testAPIClientSharedExists() {
        XCTAssertNotNil(AmachAPIClient.shared)
    }
}
