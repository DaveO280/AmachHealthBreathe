import SwiftUI
import WatchKit

/// Layout helpers for watchOS screens. The 40mm SE (162pt wide) uses a compact
/// layout; 41mm+ watches use the regular layout. Ring diameter also scales with
/// available height so tall bodies (e.g. Series 11 46mm) don't push chrome
/// into the bottom safe area.
enum WatchLayout {

    @MainActor
    private static var screenBounds: CGRect {
        WKInterfaceDevice.current().screenBounds
    }

    @MainActor
    static var isCompact: Bool {
        screenBounds.width < 170
    }

    /// Breathing ring diameter — capped by vertical space on large watches.
    @MainActor
    static var ringDiameter: CGFloat {
        if isCompact { return 88 }
        let heightBudget = screenBounds.height - 128
        return min(110, max(88, heightBudget * 0.42))
    }

    /// Bottom inset for session controls so they stay above the curved edge.
    @MainActor
    static var sessionBottomInset: CGFloat {
        isCompact ? 2 : 8
    }

    /// Pick a font size based on screen size.
    @MainActor
    static func size(_ regular: CGFloat, compact: CGFloat) -> CGFloat {
        isCompact ? compact : regular
    }
}
