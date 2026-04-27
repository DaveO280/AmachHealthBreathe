import XCTest
@testable import AmachBreatheShared

final class SubscriptionStateMachineTests: XCTestCase {

    // Fixed UTC calendar for deterministic date math
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

    // MARK: - Trial transitions

    func testTrialToPurchased() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .trial, event: .purchased), .subscribed)
    }

    func testTrialToRestored() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .trial, event: .restored), .subscribed)
    }

    func testTrialToActiveConnection() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .trial, event: .activeConnectionAchieved), .connected)
    }

    func testTrialToExpiredOnTrialEnd() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .trial, event: .trialEnded), .expired)
    }

    func testTrialIgnoresConnectionLapsed() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .trial, event: .connectionLapsed), .trial)
    }

    func testTrialIgnoresSubscriptionExpired() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .trial, event: .subscriptionExpired), .trial)
    }

    // MARK: - Subscribed transitions

    func testSubscribedToExpiredOnRevocation() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .subscribed, event: .subscriptionExpired), .expired)
    }

    func testSubscribedToConnectedOnUserCancel() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .subscribed, event: .userRequestedCancel), .connected)
    }

    func testSubscribedRenewalStaysSubscribed() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .subscribed, event: .purchased), .subscribed)
    }

    func testSubscribedIgnoresConnectionLapsed() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .subscribed, event: .connectionLapsed), .subscribed)
    }

    // MARK: - Connected transitions

    func testConnectedToPurchased() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .connected, event: .purchased), .subscribed)
    }

    func testConnectedToRestored() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .connected, event: .restored), .subscribed)
    }

    func testConnectedToExpiredOnLapse() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .connected, event: .connectionLapsed), .expired)
    }

    func testConnectedIgnoresActiveConnectionAchieved() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .connected, event: .activeConnectionAchieved), .connected)
    }

    // MARK: - Expired transitions

    func testExpiredToPurchased() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .expired, event: .purchased), .subscribed)
    }

    func testExpiredToRestored() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .expired, event: .restored), .subscribed)
    }

    func testExpiredToConnectedOnActiveConnection() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .expired, event: .activeConnectionAchieved), .connected)
    }

    func testExpiredIgnoresConnectionLapsed() {
        XCTAssertEqual(SubscriptionStateMachine.transition(from: .expired, event: .connectionLapsed), .expired)
    }

    // MARK: - Active session count

    func testActiveSessionCountIncludesSessionsInWindow() {
        let now = date("2024-06-01T12:00:00Z")
        let ts: [Date] = [
            date("2024-05-20T10:00:00Z"),   // 12 days ago — in window
            date("2024-05-03T10:00:00Z"),   // 29 days ago — in window
            date("2024-04-30T10:00:00Z"),   // 32 days ago — outside window
        ]
        XCTAssertEqual(SubscriptionStateMachine.activeSessionCount(
            uploadedTimestamps: ts, from: now, calendar: cal), 2)
    }

    func testActiveSessionCountExcludesOldSessions() {
        let now = date("2024-06-01T12:00:00Z")
        let ts: [Date] = [
            date("2024-04-01T10:00:00Z"),  // 61 days ago — outside
            date("2023-12-01T10:00:00Z"),  // way outside
        ]
        XCTAssertEqual(SubscriptionStateMachine.activeSessionCount(
            uploadedTimestamps: ts, from: now, calendar: cal), 0)
    }

    func testActiveSessionCountWindowBoundaryIsInclusive() {
        let now = date("2024-06-01T00:00:00Z")
        // Exactly 30 days before now
        let boundary = date("2024-05-02T00:00:00Z")
        XCTAssertEqual(SubscriptionStateMachine.activeSessionCount(
            uploadedTimestamps: [boundary], from: now, calendar: cal), 1)
    }

    func testIsActivelyConnectedAtThreshold() {
        let now = date("2024-06-01T12:00:00Z")
        let ts = (0..<3).map { i in date("2024-05-\(String(format: "%02d", 20 + i))T10:00:00Z") }
        XCTAssertTrue(SubscriptionStateMachine.isActivelyConnected(
            uploadedTimestamps: ts, from: now, calendar: cal))
    }

    func testIsNotActivelyConnectedBelowThreshold() {
        let now = date("2024-06-01T12:00:00Z")
        let ts = [date("2024-05-20T10:00:00Z"), date("2024-05-21T10:00:00Z")]  // only 2
        XCTAssertFalse(SubscriptionStateMachine.isActivelyConnected(
            uploadedTimestamps: ts, from: now, calendar: cal))
    }

    func testIsNotActivelyConnectedEmpty() {
        XCTAssertFalse(SubscriptionStateMachine.isActivelyConnected(
            uploadedTimestamps: [], from: Date(), calendar: cal))
    }

    // MARK: - Trial end

    func testTrialHasNotEndedBefore7Days() {
        let install = date("2024-06-01T00:00:00Z")
        let now     = date("2024-06-07T23:59:59Z")  // 6 days 23h 59m later
        XCTAssertFalse(SubscriptionStateMachine.trialHasEnded(
            installDate: install, from: now, calendar: cal))
    }

    func testTrialHasEndedAfter7Days() {
        let install = date("2024-06-01T00:00:00Z")
        let now     = date("2024-06-08T00:00:00Z")  // exactly 7 days
        XCTAssertTrue(SubscriptionStateMachine.trialHasEnded(
            installDate: install, from: now, calendar: cal))
    }

    // MARK: - Soft prompt

    func testSoftPromptShownAfter90Days() {
        let since = date("2024-01-01T00:00:00Z")
        let now   = date("2024-04-01T00:00:00Z")  // exactly 91 days later
        XCTAssertTrue(SubscriptionStateMachine.shouldShowSoftPrompt(
            connectedSince: since, from: now, hasShownBefore: false, calendar: cal))
    }

    func testSoftPromptNotShownBefore90Days() {
        let since = date("2024-01-01T00:00:00Z")
        let now   = date("2024-03-30T00:00:00Z")  // 89 days later
        XCTAssertFalse(SubscriptionStateMachine.shouldShowSoftPrompt(
            connectedSince: since, from: now, hasShownBefore: false, calendar: cal))
    }

    func testSoftPromptNotShownIfAlreadyShown() {
        let since = date("2024-01-01T00:00:00Z")
        let now   = date("2024-04-10T00:00:00Z")  // 100 days later
        XCTAssertFalse(SubscriptionStateMachine.shouldShowSoftPrompt(
            connectedSince: since, from: now, hasShownBefore: true, calendar: cal))
    }
}
