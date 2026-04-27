import WidgetKit
import AmachBreatheShared

struct ComplicationTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(
            date: Date(),
            complicationState: .ready,
            subscriptionState: .trial
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let entry = makeEntry()
        // Reload every 30 minutes — the watch app calls WidgetCenter.reloadAllTimelines()
        // on session state changes, but this acts as a backstop.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }

    // MARK: - Private

    private func makeEntry() -> ComplicationEntry {
        let defaults = UserDefaults.standard
        let inSession     = defaults.bool(forKey: ComplicationDisplayLogic.inSessionKey)
        let hasCalibration = defaults.bool(forKey: ComplicationDisplayLogic.hasCalibrationKey)
        let subRaw        = defaults.string(forKey: ComplicationDisplayLogic.subscriptionKey) ?? "trial"
        let subState      = SubscriptionState(rawValue: subRaw) ?? .trial
        let compState     = ComplicationDisplayLogic.complicationState(
            inSession: inSession, hasCalibration: hasCalibration)
        return ComplicationEntry(
            date: Date(),
            complicationState: compState,
            subscriptionState: subState
        )
    }
}
