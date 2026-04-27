import WidgetKit
import SwiftUI
import AmachBreatheShared

struct AmachBreatheComplication: Widget {

    let kind = "com.amach.breathe.complication"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: ComplicationTimelineProvider()
        ) { entry in
            ComplicationEntryView(entry: entry)
                // Deep link: tapping the corner complication launches a 5-minute quick session.
                .widgetURL(URL(string: "amachbreathe://quickstart?duration=300")!)
        }
        .configurationDisplayName("Amach Breathe")
        .description("Tap to start a quick breathing session.")
        .supportedFamilies([.accessoryCorner, .accessoryCircular, .accessoryRectangular])
    }
}
