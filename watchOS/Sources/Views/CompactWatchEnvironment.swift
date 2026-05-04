import SwiftUI
import WatchKit

/// Layout helpers for the smallest active watchOS screens — chiefly the
/// 40mm Apple Watch SE (162pt wide). Threshold of 170pt picks up only the
/// 40mm bodies; 41mm (176pt) and larger keep the regular layout.
enum WatchLayout {

    @MainActor
    static var isCompact: Bool {
        WKInterfaceDevice.current().screenBounds.width < 170
    }

    /// Pick a font size based on screen size.
    @MainActor
    static func size(_ regular: CGFloat, compact: CGFloat) -> CGFloat {
        isCompact ? compact : regular
    }
}
