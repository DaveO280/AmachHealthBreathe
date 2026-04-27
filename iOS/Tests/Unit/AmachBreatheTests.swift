import XCTest
@testable import AmachBreathe

final class AmachBreatheAppTests: XCTestCase {
    func testAppBundleIdFormat() {
        let bundle = Bundle.main.bundleIdentifier ?? ""
        // Allow empty in test runner — just verify no crash
        XCTAssertTrue(bundle.isEmpty || bundle.contains("."))
    }
}
