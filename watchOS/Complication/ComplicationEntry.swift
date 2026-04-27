import WidgetKit
import AmachBreatheShared

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let complicationState: ComplicationState
    let subscriptionState: SubscriptionState

    var displayInfo: ComplicationDisplayLogic.DisplayInfo {
        ComplicationDisplayLogic.displayInfo(
            complicationState: complicationState,
            subscriptionState: subscriptionState
        )
    }
}
