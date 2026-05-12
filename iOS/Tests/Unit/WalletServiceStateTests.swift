import XCTest
@testable import AmachBreatheShared

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

@MainActor
final class WalletServiceStateTests: XCTestCase {

    func testNormalizedEmailForCodeTrimsAndLowercases() throws {
        let email = try WalletService.normalizedEmailForCode("  USER@Example.COM \n")
        XCTAssertEqual(email, "user@example.com")
    }

    func testNormalizedEmailForCodeRejectsInvalidEmail() {
        XCTAssertThrowsError(try WalletService.normalizedEmailForCode("not-an-email")) { error in
            guard case WalletError.invalidEmail = error else {
                return XCTFail("Expected invalidEmail, got \(error)")
            }
        }
    }

    func testClearPendingEmailCodeClearsPendingStateAndError() {
        let wallet = WalletService.shared
        wallet.pendingEmail = "user@example.com"
        wallet.error = "Previous error"

        wallet.clearPendingEmailCode()

        XCTAssertNil(wallet.pendingEmail)
        XCTAssertNil(wallet.error)
    }

    func testSendEmailCodeNormalizesEmailAndSetsPendingAfterSenderSuccess() async throws {
        var sentEmails: [String] = []
        let wallet = WalletService(
            emailCodeSender: MockEmailCodeSender { email in
                sentEmails.append(email)
            },
            hasAuthenticatedBefore: false
        )

        try await wallet.sendEmailCode(to: "  USER@Example.COM \n")

        XCTAssertEqual(sentEmails, ["user@example.com"])
        XCTAssertEqual(wallet.pendingEmail, "user@example.com")
        XCTAssertNil(wallet.error)
        XCTAssertFalse(wallet.isLoading)
    }

    func testSendEmailCodeDoesNotSetPendingWhenSenderFails() async {
        let wallet = WalletService(
            emailCodeSender: MockEmailCodeSender { _ in
                throw MockEmailCodeError.failed
            },
            hasAuthenticatedBefore: false
        )

        await XCTAssertThrowsErrorAsync(try await wallet.sendEmailCode(to: "user@example.com"))

        XCTAssertNil(wallet.pendingEmail)
        XCTAssertEqual(wallet.error, "Mock send failed")
        XCTAssertFalse(wallet.isLoading)
    }

    func testSendEmailCodeRejectsInvalidEmailBeforeCallingSender() async {
        var didCallSender = false
        let wallet = WalletService(
            emailCodeSender: MockEmailCodeSender { _ in
                didCallSender = true
            },
            hasAuthenticatedBefore: false
        )

        await XCTAssertThrowsErrorAsync(try await wallet.sendEmailCode(to: "not-an-email")) { error in
            guard case WalletError.invalidEmail = error else {
                return XCTFail("Expected invalidEmail, got \(error)")
            }
        }

        XCTAssertFalse(didCallSender)
        XCTAssertNil(wallet.pendingEmail)
        XCTAssertEqual(wallet.error, WalletError.invalidEmail.localizedDescription)
        XCTAssertFalse(wallet.isLoading)
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
