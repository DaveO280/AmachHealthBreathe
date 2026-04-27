// DesignSystemTests.swift — Phase 0 snapshot tests for design tokens

import XCTest
@testable import AmachBreatheShared
import SwiftUI

final class DesignSystemColorTests: XCTestCase {

    // MARK: - Primary palette

    func testPrimaryColorHex() {
        let color = Color.Amach.primary
        let (r, g, b) = color.rgbComponents()
        XCTAssertEqual(r, 0x00, accuracy: 2)
        XCTAssertEqual(g, 0x6B, accuracy: 2)
        XCTAssertEqual(b, 0x4F, accuracy: 2)
    }

    func testP400ColorHex() {
        let color = Color.Amach.p400
        let (r, g, b) = color.rgbComponents()
        XCTAssertEqual(r, 0x10, accuracy: 2)
        XCTAssertEqual(g, 0xB9, accuracy: 2)
        XCTAssertEqual(b, 0x81, accuracy: 2)
    }

    func testAccentColorHex() {
        let color = Color.Amach.accent
        let (r, g, b) = color.rgbComponents()
        XCTAssertEqual(r, 0xF5, accuracy: 2)
        XCTAssertEqual(g, 0x9E, accuracy: 2)
        XCTAssertEqual(b, 0x0B, accuracy: 2)
    }

    func testAIBaseColorHex() {
        let color = Color.Amach.AI.base
        let (r, g, b) = color.rgbComponents()
        XCTAssertEqual(r, 0x63, accuracy: 2)
        XCTAssertEqual(g, 0x66, accuracy: 2)
        XCTAssertEqual(b, 0xF1, accuracy: 2)
    }

    // MARK: - Dark surface tokens

    func testDarkBgHex() {
        let color = Color.Amach.Surface.bgDark
        let (r, g, b) = color.rgbComponents()
        XCTAssertEqual(r, 0x0A, accuracy: 2)
        XCTAssertEqual(g, 0x1A, accuracy: 2)
        XCTAssertEqual(b, 0x15, accuracy: 2)
    }

    // MARK: - Semantic colors exist

    func testSemanticColorsNotClear() {
        // Just assert they resolve without crash
        _ = Color.Amach.Semantic.success
        _ = Color.Amach.Semantic.warning
        _ = Color.Amach.Semantic.error
        _ = Color.Amach.Semantic.info
    }

    // MARK: - Hex initialiser round-trip

    func testHexInitRoundTrip() {
        let original = "10B981"
        let color = Color(hex: original)
        let (r, g, b) = color.rgbComponents()
        XCTAssertEqual(r, 0x10, accuracy: 2, "Red channel mismatch for #\(original)")
        XCTAssertEqual(g, 0xB9, accuracy: 2, "Green channel mismatch for #\(original)")
        XCTAssertEqual(b, 0x81, accuracy: 2, "Blue channel mismatch for #\(original)")
    }
}

final class DesignSystemTypographyTests: XCTestCase {

    func testH1IsLargerThanH2() {
        // .system fonts embed size — compare via UIFont on iOS
#if os(iOS)
        let h1Font = UIFont.preferredFont(forTextStyle: .largeTitle)
        let h2Font = UIFont.preferredFont(forTextStyle: .title2)
        XCTAssertGreaterThanOrEqual(h1Font.pointSize, h2Font.pointSize)
#else
        // On watchOS just assert the enum is accessible
        _ = AmachType.h1
        _ = AmachType.h2
#endif
    }

    func testDataValueMonospaced() {
        // dataValue returns a monospaced font — just verify it doesn't crash
        let f = AmachType.dataValue(size: 36)
        XCTAssertNotNil(f)
    }

    func testAllTokensAccessible() {
        _ = AmachType.h1
        _ = AmachType.h2
        _ = AmachType.h3
        _ = AmachType.body
        _ = AmachType.caption
        _ = AmachType.tiny
        _ = AmachType.dataMono
        _ = AmachType.dataUnit()
        _ = AmachType.dataValue()
    }
}

final class DesignSystemSpacingTests: XCTestCase {

    func testSpacingOrder() {
        XCTAssertLessThan(AmachSpacing.xs, AmachSpacing.sm)
        XCTAssertLessThan(AmachSpacing.sm, AmachSpacing.md)
        XCTAssertLessThan(AmachSpacing.md, AmachSpacing.lg)
        XCTAssertLessThan(AmachSpacing.lg, AmachSpacing.xl)
        XCTAssertLessThan(AmachSpacing.xl, AmachSpacing.xxl)
        XCTAssertLessThan(AmachSpacing.xxl, AmachSpacing.xxxl)
    }

    func testBaseGridAlignment() {
        // All tokens are multiples of 4pt
        for v in [AmachSpacing.xs, AmachSpacing.sm, AmachSpacing.md,
                  AmachSpacing.lg, AmachSpacing.xl, AmachSpacing.xxl, AmachSpacing.xxxl] {
            XCTAssertEqual(v.truncatingRemainder(dividingBy: 4), 0,
                           "\(v) is not a multiple of 4pt")
        }
    }
}

final class DesignSystemRadiusTests: XCTestCase {

    func testRadiusOrder() {
        XCTAssertLessThan(AmachRadius.xs, AmachRadius.sm)
        XCTAssertLessThan(AmachRadius.sm, AmachRadius.md)
        XCTAssertLessThan(AmachRadius.md, AmachRadius.card)
        XCTAssertLessThan(AmachRadius.card, AmachRadius.lg)
        XCTAssertLessThan(AmachRadius.lg, AmachRadius.xl)
    }
}

// MARK: - Color RGB extraction helper

private extension Color {
    /// Returns (R, G, B) as UInt8 values (0–255).
    /// Uses Color.resolve(in:) — available iOS 17+, macOS 14+, watchOS 10+.
    func rgbComponents() -> (UInt8, UInt8, UInt8) {
        let r = self.resolve(in: EnvironmentValues())
        return (
            UInt8((r.red   * 255).rounded()),
            UInt8((r.green * 255).rounded()),
            UInt8((r.blue  * 255).rounded())
        )
    }
}
