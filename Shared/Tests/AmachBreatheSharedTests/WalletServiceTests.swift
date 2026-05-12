// WalletServiceTests.swift — Phase 0: PBKDF2 key derivation + Privy init

import XCTest
@testable import AmachBreatheShared

#if os(iOS)
private struct MockEmailCodeSender: WalletEmailCodeSending {
    var sendHandler: (String) async throws -> Void

    func sendCode(to email: String) async throws {
        try await sendHandler(email)
    }
}

private enum MockEmailCodeError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Mock send failed"
    }
}

final class WalletServicePBKDF2Tests: XCTestCase {

    // MARK: - PBKDF2 Derivation

    func testDeriveEncryptionKeyProducesHexString() throws {
        let sig  = "0x" + String(repeating: "ab", count: 65)
        let addr = "0x" + String(repeating: "12", count: 20)
        let key  = try WalletService.deriveEncryptionKeyPBKDF2(signatureHex: sig, walletAddress: addr)

        XCTAssertEqual(key.count, 64, "Key should be 32 bytes = 64 hex chars")
        XCTAssertTrue(key.allSatisfy { "0123456789abcdef".contains($0) }, "Key should be lowercase hex")
    }

    func testDeriveEncryptionKeyIsDeterministic() throws {
        let sig  = "0x" + String(repeating: "cd", count: 65)
        let addr = "0x1234567890abcdef1234567890abcdef12345678"

        let key1 = try WalletService.deriveEncryptionKeyPBKDF2(signatureHex: sig, walletAddress: addr)
        let key2 = try WalletService.deriveEncryptionKeyPBKDF2(signatureHex: sig, walletAddress: addr)

        XCTAssertEqual(key1, key2, "Same inputs must always produce the same key")
    }

    func testDeriveEncryptionKeyChangesWithDifferentSig() throws {
        let addr = "0x1234567890abcdef1234567890abcdef12345678"
        let sig1 = "0x" + String(repeating: "aa", count: 65)
        let sig2 = "0x" + String(repeating: "bb", count: 65)

        let key1 = try WalletService.deriveEncryptionKeyPBKDF2(signatureHex: sig1, walletAddress: addr)
        let key2 = try WalletService.deriveEncryptionKeyPBKDF2(signatureHex: sig2, walletAddress: addr)

        XCTAssertNotEqual(key1, key2)
    }

    func testDeriveEncryptionKeyStripsOxPrefix() throws {
        let sig     = "0x" + String(repeating: "ab", count: 65)
        let sigNoOx = String(repeating: "ab", count: 65)
        let addr    = "0x1234567890abcdef1234567890abcdef12345678"

        let key1 = try WalletService.deriveEncryptionKeyPBKDF2(signatureHex: sig, walletAddress: addr)
        let key2 = try WalletService.deriveEncryptionKeyPBKDF2(signatureHex: sigNoOx, walletAddress: addr)

        XCTAssertEqual(key1, key2, "0x prefix should be stripped before derivation")
    }

    func testDeriveEncryptionKeyOutputLength32Bytes() throws {
        let key = try WalletService.deriveEncryptionKeyPBKDF2(
            signatureHex: "0x" + String(repeating: "ef", count: 65),
            walletAddress: "0xabcdef1234567890abcdef1234567890abcdef12"
        )
        XCTAssertEqual(key.count, 64)
    }

    // MARK: - Hex utilities

    func testHexToBytesRoundTrip() throws {
        let hex = "deadbeef"
        let bytes = try WalletService.hexToBytes(hex)
        XCTAssertEqual(bytes, [0xde, 0xad, 0xbe, 0xef])
    }

    func testHexToBytesOddLengthThrows() {
        XCTAssertThrowsError(try WalletService.hexToBytes("abc"))
    }

    func testHexToBytesEmptyInput() throws {
        let bytes = try WalletService.hexToBytes("")
        XCTAssertTrue(bytes.isEmpty)
    }

    // MARK: - Privy init (smoke test — no real SDK required)

    @MainActor
    func testWalletServiceSharedExists() {
        XCTAssertNotNil(WalletService.shared)
    }

    @MainActor
    func testWalletServiceInitiallyDisconnected() {
        // Fresh state should be disconnected (state is persisted; just verify type)
        let ws = WalletService.shared
        XCTAssertFalse(ws.isLoading)
    }

    @MainActor
    func testNormalizedEmailForCodeTrimsAndLowercases() throws {
        let email = try WalletService.normalizedEmailForCode("  USER@Example.COM \n")
        XCTAssertEqual(email, "user@example.com")
    }

    @MainActor
    func testNormalizedEmailForCodeRejectsInvalidEmail() {
        XCTAssertThrowsError(try WalletService.normalizedEmailForCode("not-an-email")) { error in
            guard case WalletError.invalidEmail = error else {
                return XCTFail("Expected invalidEmail, got \(error)")
            }
        }
    }

    @MainActor
    func testClearPendingEmailCodeClearsPendingStateAndError() {
        let ws = WalletService.shared
        ws.pendingEmail = "user@example.com"
        ws.error = "Previous error"

        ws.clearPendingEmailCode()

        XCTAssertNil(ws.pendingEmail)
        XCTAssertNil(ws.error)
    }

    @MainActor
    func testSendEmailCodeNormalizesEmailAndSetsPendingAfterSenderSuccess() async throws {
        var sentEmails: [String] = []
        let ws = WalletService(
            emailCodeSender: MockEmailCodeSender { email in
                sentEmails.append(email)
            },
            hasAuthenticatedBefore: false
        )

        try await ws.sendEmailCode(to: "  USER@Example.COM \n")

        XCTAssertEqual(sentEmails, ["user@example.com"])
        XCTAssertEqual(ws.pendingEmail, "user@example.com")
        XCTAssertNil(ws.error)
        XCTAssertFalse(ws.isLoading)
    }

    @MainActor
    func testSendEmailCodeDoesNotSetPendingWhenSenderFails() async {
        let ws = WalletService(
            emailCodeSender: MockEmailCodeSender { _ in
                throw MockEmailCodeError.failed
            },
            hasAuthenticatedBefore: false
        )

        await XCTAssertThrowsErrorAsync(try await ws.sendEmailCode(to: "user@example.com"))

        XCTAssertNil(ws.pendingEmail)
        XCTAssertEqual(ws.error, "Mock send failed")
        XCTAssertFalse(ws.isLoading)
    }

    @MainActor
    func testSendEmailCodeRejectsInvalidEmailBeforeCallingSender() async {
        var didCallSender = false
        let ws = WalletService(
            emailCodeSender: MockEmailCodeSender { _ in
                didCallSender = true
            },
            hasAuthenticatedBefore: false
        )

        await XCTAssertThrowsErrorAsync(try await ws.sendEmailCode(to: "not-an-email")) { error in
            guard case WalletError.invalidEmail = error else {
                return XCTFail("Expected invalidEmail, got \(error)")
            }
        }

        XCTAssertFalse(didCallSender)
        XCTAssertNil(ws.pendingEmail)
        XCTAssertEqual(ws.error, WalletError.invalidEmail.localizedDescription)
        XCTAssertFalse(ws.isLoading)
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        try await expression()
        XCTFail(message(), file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
#endif
