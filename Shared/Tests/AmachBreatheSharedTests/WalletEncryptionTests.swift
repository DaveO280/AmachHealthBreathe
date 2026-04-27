import XCTest
@testable import AmachBreatheShared

/// Tests WalletCrypto PBKDF2 derivation and WalletEncryptionKey Codable round-trip.
/// PBKDF2 derivation MUST be deterministic and match walletEncryption.ts output.
final class WalletEncryptionTests: XCTestCase {

    // MARK: - PBKDF2 Determinism

    func testDerivationIsDeterministic() throws {
        let sig = "0x" + String(repeating: "ab", count: 65)
        let address = "0xabc0000000000000000000000000000000abc001"
        let key1 = try WalletCrypto.deriveEncryptionKey(signatureHex: sig, walletAddress: address)
        let key2 = try WalletCrypto.deriveEncryptionKey(signatureHex: sig, walletAddress: address)
        XCTAssertEqual(key1, key2, "PBKDF2 must be deterministic")
    }

    func testDerivationProduces64HexChars() throws {
        let sig = "0x" + String(repeating: "cd", count: 65)
        let address = "0xabc0000000000000000000000000000000abc001"
        let key = try WalletCrypto.deriveEncryptionKey(signatureHex: sig, walletAddress: address)
        XCTAssertEqual(key.count, 64, "32 bytes = 64 hex chars")
        XCTAssertTrue(key.allSatisfy { $0.isHexDigit }, "Key must be lowercase hex")
    }

    func testDifferentSignaturesProduceDifferentKeys() throws {
        let address = "0xabc0000000000000000000000000000000abc001"
        let key1 = try WalletCrypto.deriveEncryptionKey(
            signatureHex: "0x" + String(repeating: "aa", count: 65), walletAddress: address)
        let key2 = try WalletCrypto.deriveEncryptionKey(
            signatureHex: "0x" + String(repeating: "bb", count: 65), walletAddress: address)
        XCTAssertNotEqual(key1, key2)
    }

    func testDifferentAddressesProduceDifferentKeys() throws {
        let sig = "0x" + String(repeating: "ab", count: 65)
        let key1 = try WalletCrypto.deriveEncryptionKey(
            signatureHex: sig, walletAddress: "0xaaa0000000000000000000000000000000aaa001")
        let key2 = try WalletCrypto.deriveEncryptionKey(
            signatureHex: sig, walletAddress: "0xbbb0000000000000000000000000000000bbb002")
        XCTAssertNotEqual(key1, key2)
    }

    func testDerivationStripsOxPrefix() throws {
        let address = "0xabc0000000000000000000000000000000abc001"
        let sigWithPrefix    = "0x" + String(repeating: "ef", count: 65)
        let sigWithoutPrefix = String(repeating: "ef", count: 65)
        let keyWith    = try WalletCrypto.deriveEncryptionKey(signatureHex: sigWithPrefix, walletAddress: address)
        let keyWithout = try WalletCrypto.deriveEncryptionKey(signatureHex: sigWithoutPrefix, walletAddress: address)
        XCTAssertEqual(keyWith, keyWithout, "0x prefix must be stripped automatically")
    }

    func testDerivationWithTypicalWalletAddress() throws {
        let mockSig = "0x" + String(repeating: "ab", count: 65)
        let key = try WalletCrypto.deriveEncryptionKey(
            signatureHex: mockSig,
            walletAddress: "0xd8da6bf26964af9d7eed9e03e53415d37aa96045")
        XCTAssertEqual(key.count, 64)
    }

    // MARK: - hexToBytes

    func testHexToBytes() throws {
        let bytes = try WalletCrypto.hexToBytes("deadbeef")
        XCTAssertEqual(bytes, [0xDE, 0xAD, 0xBE, 0xEF])
    }

    func testHexToBytesOddLengthThrows() {
        XCTAssertThrowsError(try WalletCrypto.hexToBytes("abc"))
    }

    func testHexToBytesEmpty() throws {
        let bytes = try WalletCrypto.hexToBytes("")
        XCTAssertTrue(bytes.isEmpty)
    }

    // MARK: - WalletEncryptionKey Codable

    func testWalletKeyEncodesAsWebFormat() throws {
        let key = WalletEncryptionKey(
            walletAddress: "0xabc", encryptionKey: "abc123",
            signature: "0xsig", timestamp: 1_700_000_000)
        let data = try JSONEncoder().encode(key)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["walletAddress"] as? String, "0xabc")
        XCTAssertEqual(json["key"] as? String, "abc123")
        XCTAssertEqual(json["derivedAt"] as? Int, 1_700_000_000)
        XCTAssertNil(json["encryptionKey"])
        XCTAssertNil(json["timestamp"])
    }

    func testWalletKeyRoundTrip() throws {
        let key = WalletEncryptionKey(
            walletAddress: "0xabc", encryptionKey: "abc123",
            signature: "0xsig", timestamp: 1_700_000_000)
        let data = try JSONEncoder().encode(key)
        let decoded = try JSONDecoder().decode(WalletEncryptionKey.self, from: data)
        XCTAssertEqual(decoded.walletAddress, key.walletAddress)
        XCTAssertEqual(decoded.encryptionKey, key.encryptionKey)
        XCTAssertEqual(decoded.signature, key.signature)
        XCTAssertEqual(decoded.timestamp, key.timestamp)
    }

    func testWalletKeyDecodesLegacyFields() throws {
        let legacyJSON = """
        { "walletAddress":"0xabc", "encryptionKey":"abc123", "signature":"0xsig", "timestamp":1700000000 }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WalletEncryptionKey.self, from: legacyJSON)
        XCTAssertEqual(decoded.encryptionKey, "abc123")
        XCTAssertEqual(decoded.timestamp, 1_700_000_000)
    }
}
