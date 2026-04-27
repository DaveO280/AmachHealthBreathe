import XCTest
@testable import AmachBreatheShared

/// Boundary conditions and no-op transitions not covered in SubscriptionStateMachineTests.
/// Coverage goal: every (state, event) pair is exercised at least once.
final class SubscriptionEdgeCaseTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: iso)!
    }

    // MARK: - No-op transitions (default case coverage)

    func testTrial_userRequestedCancel_isNoOp() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .trial, event: .userRequestedCancel), .trial)
    }

    func testSubscribed_activeConnectionAchieved_isNoOp() {
        // Already subscribed — connection status doesn't change state
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .subscribed, event: .activeConnectionAchieved), .subscribed)
    }

    func testSubscribed_trialEnded_isNoOp() {
        // Trial end is irrelevant once subscribed
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .subscribed, event: .trialEnded), .subscribed)
    }

    func testSubscribed_restored_staysSubscribed() {
        // Restore while already subscribed: renews confirmation but no state change
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .subscribed, event: .restored), .subscribed)
    }

    func testConnected_trialEnded_isNoOp() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .connected, event: .trialEnded), .connected)
    }

    func testConnected_subscriptionExpired_isNoOp() {
        // Connected users have no subscription to expire
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .connected, event: .subscriptionExpired), .connected)
    }

    func testConnected_userRequestedCancel_isNoOp() {
        // Already on free connected tier
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .connected, event: .userRequestedCancel), .connected)
    }

    func testExpired_trialEnded_isNoOp() {
        // Trial already ran out — can't end twice
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .expired, event: .trialEnded), .expired)
    }

    func testExpired_subscriptionExpired_isNoOp() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .expired, event: .subscriptionExpired), .expired)
    }

    func testExpired_userRequestedCancel_isNoOp() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .expired, event: .userRequestedCancel), .expired)
    }

    // MARK: - Complete state-transition matrix (all 28 pairs verified)

    func testCompleteTransitionMatrix() {
        typealias Pair = (SubscriptionState, SubscriptionEvent, SubscriptionState)
        let matrix: [Pair] = [
            // .trial
            (.trial, .purchased,                .subscribed),
            (.trial, .restored,                 .subscribed),
            (.trial, .activeConnectionAchieved, .connected),
            (.trial, .trialEnded,               .expired),
            (.trial, .connectionLapsed,         .trial),
            (.trial, .subscriptionExpired,      .trial),
            (.trial, .userRequestedCancel,      .trial),
            // .subscribed
            (.subscribed, .purchased,                .subscribed),
            (.subscribed, .restored,                 .subscribed),
            (.subscribed, .activeConnectionAchieved, .subscribed),
            (.subscribed, .trialEnded,               .subscribed),
            (.subscribed, .connectionLapsed,         .subscribed),
            (.subscribed, .subscriptionExpired,      .expired),
            (.subscribed, .userRequestedCancel,      .connected),
            // .connected
            (.connected, .purchased,                .subscribed),
            (.connected, .restored,                 .subscribed),
            (.connected, .activeConnectionAchieved, .connected),
            (.connected, .trialEnded,               .connected),
            (.connected, .connectionLapsed,         .expired),
            (.connected, .subscriptionExpired,      .connected),
            (.connected, .userRequestedCancel,      .connected),
            // .expired
            (.expired, .purchased,                .subscribed),
            (.expired, .restored,                 .subscribed),
            (.expired, .activeConnectionAchieved, .connected),
            (.expired, .trialEnded,               .expired),
            (.expired, .connectionLapsed,         .expired),
            (.expired, .subscriptionExpired,      .expired),
            (.expired, .userRequestedCancel,      .expired),
        ]
        for (from, event, expected) in matrix {
            let got = SubscriptionStateMachine.transition(from: from, event: event)
            XCTAssertEqual(got, expected,
                "transition(\(from), \(event)) → \(got), expected \(expected)")
        }
    }

    // MARK: - Sequential multi-hop transitions

    func testFullFreeLifecycle_trialToConnectedToExpiredToSubscribed() {
        var state: SubscriptionState = .trial
        state = SubscriptionStateMachine.transition(from: state, event: .activeConnectionAchieved)
        XCTAssertEqual(state, .connected)
        state = SubscriptionStateMachine.transition(from: state, event: .connectionLapsed)
        XCTAssertEqual(state, .expired)
        state = SubscriptionStateMachine.transition(from: state, event: .purchased)
        XCTAssertEqual(state, .subscribed)
    }

    func testSubscriptionCancelAndLapse() {
        var state: SubscriptionState = .subscribed
        state = SubscriptionStateMachine.transition(from: state, event: .userRequestedCancel)
        XCTAssertEqual(state, .connected)
        state = SubscriptionStateMachine.transition(from: state, event: .connectionLapsed)
        XCTAssertEqual(state, .expired)
        state = SubscriptionStateMachine.transition(from: state, event: .activeConnectionAchieved)
        XCTAssertEqual(state, .connected)
    }

    func testTrialExpiry_thenPurchase_thenCancel() {
        var state: SubscriptionState = .trial
        state = SubscriptionStateMachine.transition(from: state, event: .trialEnded)
        XCTAssertEqual(state, .expired)
        state = SubscriptionStateMachine.transition(from: state, event: .purchased)
        XCTAssertEqual(state, .subscribed)
        state = SubscriptionStateMachine.transition(from: state, event: .userRequestedCancel)
        XCTAssertEqual(state, .connected)
    }

    // MARK: - Trial end boundary: second-level precision

    func testTrialHasNotEnded_oneMomentBefore7Days() {
        let install = date("2024-06-01T00:00:00Z")
        let justBefore = date("2024-06-07T23:59:59Z") // 7 days - 1 s
        XCTAssertFalse(SubscriptionStateMachine.trialHasEnded(
            installDate: install, from: justBefore, calendar: cal))
    }

    func testTrialHasEnded_exactlyAt7Days() {
        let install = date("2024-06-01T00:00:00Z")
        let exact = date("2024-06-08T00:00:00Z")
        XCTAssertTrue(SubscriptionStateMachine.trialHasEnded(
            installDate: install, from: exact, calendar: cal))
    }

    func testTrialHasEnded_wellAfter7Days() {
        let install = date("2024-01-01T00:00:00Z")
        let twoYearsLater = date("2026-01-01T00:00:00Z")
        XCTAssertTrue(SubscriptionStateMachine.trialHasEnded(
            installDate: install, from: twoYearsLater, calendar: cal))
    }

    // MARK: - Soft prompt boundary: second-level precision

    func testSoftPrompt_exactlyAt90Days() {
        let since = date("2024-01-01T00:00:00Z")
        let exact90 = cal.date(byAdding: .day, value: 90, to: since)!
        XCTAssertTrue(SubscriptionStateMachine.shouldShowSoftPrompt(
            connectedSince: since, from: exact90, hasShownBefore: false, calendar: cal))
    }

    func testSoftPrompt_oneMomentBefore90Days() {
        let since = date("2024-01-01T00:00:00Z")
        let justBefore = cal.date(byAdding: .second, value: -1,
            to: cal.date(byAdding: .day, value: 90, to: since)!)!
        XCTAssertFalse(SubscriptionStateMachine.shouldShowSoftPrompt(
            connectedSince: since, from: justBefore, hasShownBefore: false, calendar: cal))
    }

    func testSoftPrompt_hasShownBefore_alwaysFalse() {
        let since = date("2024-01-01T00:00:00Z")
        let wayLater = date("2030-01-01T00:00:00Z")
        XCTAssertFalse(SubscriptionStateMachine.shouldShowSoftPrompt(
            connectedSince: since, from: wayLater, hasShownBefore: true, calendar: cal))
    }

    // MARK: - activeSessionCount edge cases

    func testActiveSessionCount_futureDatesCountIfInWindow() {
        // Future timestamps are still >= windowStart, so they count.
        // This is expected behaviour (clock skew tolerance).
        let now = date("2024-06-01T00:00:00Z")
        let future = date("2024-06-10T00:00:00Z") // 9 days in the future
        XCTAssertEqual(SubscriptionStateMachine.activeSessionCount(
            uploadedTimestamps: [future], from: now, calendar: cal), 1)
    }

    func testActiveSessionCount_exactlyOneDayInsideWindow() {
        let now = date("2024-06-01T00:00:00Z")
        let oneInsideWindow = date("2024-05-02T00:00:01Z") // 29 days 23h 59m 59s ago
        XCTAssertEqual(SubscriptionStateMachine.activeSessionCount(
            uploadedTimestamps: [oneInsideWindow], from: now, calendar: cal), 1)
    }

    func testActiveSessionCount_duplicateTimestamps() {
        let now = date("2024-06-01T00:00:00Z")
        let ts = date("2024-05-20T10:00:00Z")
        // Duplicates count as separate sessions (upload model stores each separately)
        XCTAssertEqual(SubscriptionStateMachine.activeSessionCount(
            uploadedTimestamps: [ts, ts, ts], from: now, calendar: cal), 3)
    }

    func testIsActivelyConnected_exactlyAtThreshold() {
        let now = date("2024-06-01T00:00:00Z")
        let sessions = (0..<SubscriptionStateMachine.connectionThreshold).map { i in
            date("2024-05-\(String(format: "%02d", 20 + i))T10:00:00Z")
        }
        XCTAssertTrue(SubscriptionStateMachine.isActivelyConnected(
            uploadedTimestamps: sessions, from: now, calendar: cal))
    }

    func testIsActivelyConnected_oneUnderThreshold() {
        let now = date("2024-06-01T00:00:00Z")
        let sessions = (0..<(SubscriptionStateMachine.connectionThreshold - 1)).map { i in
            date("2024-05-\(String(format: "%02d", 20 + i))T10:00:00Z")
        }
        XCTAssertFalse(SubscriptionStateMachine.isActivelyConnected(
            uploadedTimestamps: sessions, from: now, calendar: cal))
    }

    // MARK: - Constants contract (changes here break cross-platform parity)

    func testConstantsAreStable() {
        XCTAssertEqual(SubscriptionStateMachine.connectionThreshold, 3)
        XCTAssertEqual(SubscriptionStateMachine.rollingWindowDays, 30)
        XCTAssertEqual(SubscriptionStateMachine.trialDays, 7)
        XCTAssertEqual(SubscriptionStateMachine.softPromptDays, 90)
    }
}
