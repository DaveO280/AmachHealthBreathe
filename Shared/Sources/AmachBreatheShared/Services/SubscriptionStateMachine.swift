import Foundation

// MARK: - Subscription events (explicit triggers — no auto-transitions)

public enum SubscriptionEvent: Sendable, Equatable {
    case purchased                  // StoreKit transaction verified
    case subscriptionExpired        // StoreKit entitlement no longer active
    case activeConnectionAchieved   // ≥3 sessions uploaded in rolling 30 days
    case connectionLapsed           // <3 sessions uploaded in rolling 30 days
    case userRequestedCancel        // Subscribed user chose free connected tier
    case trialEnded                 // 7-day trial period elapsed without purchase
    case restored                   // StoreKit restore found active subscription
}

// MARK: - State machine (pure — no I/O, deterministic, testable)

public enum SubscriptionStateMachine {

    // MARK: - Constants

    public static let connectionThreshold = 3       // sessions required in 30 days
    public static let rollingWindowDays   = 30
    public static let trialDays           = 7
    public static let softPromptDays      = 90

    // MARK: - Active connection counting

    /// Sessions with uploadStatus == .uploaded whose timestamp falls within the rolling window.
    /// Pass the calendar explicitly so tests can inject a fixed locale.
    public static func activeSessionCount(
        uploadedTimestamps: [Date],
        from now: Date,
        calendar: Calendar = .current
    ) -> Int {
        let windowStart = calendar.date(byAdding: .day, value: -rollingWindowDays, to: now)!
        // Upper bound: timestamps > now are future-dated (clock-skew or manipulation) and
        // must not count — they haven't actually occurred from the device's perspective.
        return uploadedTimestamps.filter { $0 >= windowStart && $0 <= now }.count
    }

    public static func isActivelyConnected(
        uploadedTimestamps: [Date],
        from now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        activeSessionCount(uploadedTimestamps: uploadedTimestamps, from: now, calendar: calendar)
            >= connectionThreshold
    }

    // MARK: - Transition

    /// Apply an event to the current state, returning the new state.
    /// States are independent — no implicit side effects.
    public static func transition(
        from state: SubscriptionState,
        event: SubscriptionEvent
    ) -> SubscriptionState {
        switch (state, event) {

        // From trial
        case (.trial, .purchased):              return .subscribed
        case (.trial, .restored):               return .subscribed
        case (.trial, .activeConnectionAchieved): return .connected
        case (.trial, .trialEnded):             return .expired

        // From subscribed
        case (.subscribed, .subscriptionExpired):   return .expired
        case (.subscribed, .userRequestedCancel):   return .connected  // caller must verify threshold first
        case (.subscribed, .purchased):             return .subscribed  // renewal

        // From connected
        case (.connected, .purchased):              return .subscribed
        case (.connected, .restored):               return .subscribed
        case (.connected, .connectionLapsed):       return .expired

        // From expired
        case (.expired, .purchased):                return .subscribed
        case (.expired, .restored):                 return .subscribed
        case (.expired, .activeConnectionAchieved): return .connected

        // All other combinations are no-ops (state unchanged)
        default:                                    return state
        }
    }

    // MARK: - Trial eligibility

    public static func trialHasEnded(
        installDate: Date,
        from now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let trialEnd = calendar.date(byAdding: .day, value: trialDays, to: installDate)!
        return now >= trialEnd
    }

    // MARK: - Soft support prompt

    public static func shouldShowSoftPrompt(
        connectedSince: Date,
        from now: Date,
        hasShownBefore: Bool,
        calendar: Calendar = .current
    ) -> Bool {
        guard !hasShownBefore else { return false }
        let threshold = calendar.date(byAdding: .day, value: softPromptDays, to: connectedSince)!
        return now >= threshold
    }
}
