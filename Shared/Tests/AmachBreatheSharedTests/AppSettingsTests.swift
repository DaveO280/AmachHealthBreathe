import XCTest
@testable import AmachBreatheShared

final class AppSettingsTests: XCTestCase {

    // MARK: - Defaults

    func testDefaultValues() {
        let s = AppSettings.default
        XCTAssertEqual(s.defaultRatio, .fourToSix)
        XCTAssertEqual(s.reminderSecondsFromMidnight, [])
        XCTAssertEqual(s.audioVolume, 0.5, accuracy: 0.001)
        XCTAssertEqual(s.pacerStyle, .ring)
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        var settings = AppSettings.default
        settings.defaultRatio = .oneToOne
        settings.reminderSecondsFromMidnight = [28800, 72000]  // 8am, 8pm
        settings.audioVolume = 0.75
        settings.pacerStyle = .text

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.defaultRatio, .oneToOne)
        XCTAssertEqual(decoded.reminderSecondsFromMidnight, [28800, 72000])
        XCTAssertEqual(decoded.audioVolume, 0.75, accuracy: 0.001)
        XCTAssertEqual(decoded.pacerStyle, .text)
    }

    func testCodableRoundTripMinimalPacerStyle() throws {
        var settings = AppSettings.default
        settings.pacerStyle = .minimal

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.pacerStyle, .minimal)
    }

    func testCodableRoundTripEmptyReminders() throws {
        let data = try JSONEncoder().encode(AppSettings.default)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.reminderSecondsFromMidnight, [])
    }

    // MARK: - Equatable

    func testEquatableSameValues() {
        XCTAssertEqual(AppSettings.default, AppSettings.default)
    }

    func testEquatableDifferentRatio() {
        var a = AppSettings.default
        var b = AppSettings.default
        a.defaultRatio = .oneToOne
        b.defaultRatio = .fourToSix
        XCTAssertNotEqual(a, b)
    }

    func testEquatableDifferentVolume() {
        var a = AppSettings.default
        var b = AppSettings.default
        a.audioVolume = 0.3
        b.audioVolume = 0.8
        XCTAssertNotEqual(a, b)
    }

    // MARK: - PacerStyle allCases

    func testPacerStyleAllCases() {
        let styles = AppSettings.PacerStyle.allCases
        XCTAssertTrue(styles.contains(.ring))
        XCTAssertTrue(styles.contains(.text))
        XCTAssertTrue(styles.contains(.minimal))
        XCTAssertEqual(styles.count, 3)
    }

    func testPacerStyleRawValues() {
        XCTAssertEqual(AppSettings.PacerStyle.ring.rawValue, "ring")
        XCTAssertEqual(AppSettings.PacerStyle.text.rawValue, "text")
        XCTAssertEqual(AppSettings.PacerStyle.minimal.rawValue, "minimal")
    }
}
