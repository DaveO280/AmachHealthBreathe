import SwiftUI
import WidgetKit
import AmachBreatheShared

struct ComplicationEntryView: View {

    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCorner:
            cornerView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            cornerView
        }
    }

    // MARK: - Corner (primary, small footprint)

    private var cornerView: some View {
        Image(systemName: entry.displayInfo.iconName)
            .foregroundStyle(accentColor)
            .widgetLabel {
                Text(entry.displayInfo.label)
            }
    }

    // MARK: - Circular

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: entry.displayInfo.iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(accentColor)
                Text(entry.displayInfo.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Rectangular

    private var rectangularView: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.displayInfo.iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Amach Breathe")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(entry.displayInfo.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Helpers

    private var accentColor: Color {
        Color(hex: entry.displayInfo.accentColorHex)
    }
}
