import XCTest
import AmachBreatheShared

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
}
