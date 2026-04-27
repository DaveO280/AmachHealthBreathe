import XCTest
@testable import AmachBreatheShared

/// Stress tests for the subscription threshold logic under clock edge cases.
///
/// The 30-day rolling window controls free vs. paid access. These tests verify:
///   - Future-dated sessions (clock ahead / manipulation) are rejected
///   - Exactly-at-boundary sessions count or don't count as specified
///   - A behind-the-wall clock is lenient (expected) but doesn't grant infinite access
///   - Mixed timestamp scenarios are deterministic
///   - Rapid within-day state transitions are handled correctly
final class SubscriptionClockEdgeCaseTests: XCTestCase {

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

    // MARK: - Future timestamps must not count

    func testFutureTimestamp_oneDayAhead_notCounted() {
        let now = date("2024-06-01T00:00:00Z")
        let tomorrow = date("2024-06-02T00:00:00Z")
        XCTAssertEqual(SubscriptionStateMachine.activeSessionCount(
            uploadedTimestamps: [tomorrow], from: now, calendar: cal), 0,
            "Session 1 day in the future must not count toward threshold")
    }

    func testFutureTimestamp_oneHourAhead_notCounted() {
        let now = date("2024-06-01T12:00:00Z")
        let oneHourAhead = date("2024-06-01T13:00:00Z")
        XCTAssertEqual(SubscriptionStateMachine.activeSessionCount(
            uploadedTimestamps: [oneHourAhead], from: now, calendar: cal), 0,
            "Session 1 hour in the future must not count")
    }

    func testFutureTimestamp_oneSecondAhead_notCounted() {
        let now = date("2024-06-01T12:00:00Z")
        let oneSecAhead = now.addingTimeInterval(1)
        XCTAssertEqual(SubscriptionStateMachine.activeSessionCount(
            uploadedTimestamps: [oneSecAhead], from: now, calendar: cal), 0,
            "Session 1 second in the future must not count (clock manipulation guard)")
    }

    func testSessionAtExactlyNow_counts() {
        // A session timestamped at exactly 'now' is valid — just completed
        let now = date("2024-06-01T12:00:00Z")
        XCTAssertEqual(SubscriptionStateMachine.activeSessionCount(
            uploadedTimestamps: [now], from: now, calendar: cal), 1,
            "Session at exactly 'now' must count (just completed)")
    }

    func testMixedFutureAndPast_onlyPastCounts() {
        let now = date("2024-06-01T12:00:00Z")
        let past1 = date("2024-05-20T10:00:00Z") // 12 days ago — in window
        let past2 = date("2024-05-15T10:00:00Z") // 17 days ago — in window
        let future = date("2024-06-15T00:00:00Z") // 14 days in the future — must not count
        XCTAssertEqual(SubscriptionStateMachine.activeSessionCount(
            uploadedTimestamps: [past1, past2, future], from: now, calendar: cal), 2,
            "Only past sessions should count; future session must be excluded")
    }

    func testThreeFutureSessions_notActive() {
        let now = date("2024-06-01T00:00:00Z")
        let sessions = (1...3).map { i in now.addingTimeInterval(Double(i) * 86400) }
        XCTAssertFalse(SubscriptionStateMachine.isActivelyConnected(
            uploadedTimestamps: sessions, from: now, calendar: cal),
            "3 future-dated sessions must not establish active connection")
    }

    // MARK: - 30-day window boundaries

    func testSessionExactlyAtWindowStart_counted() {
        let now = date("2024-06-01T00:00:00Z")
        let windowStart = cal.date(byAdding: .day, value: -30, to: now)!
        // Exactly at boundary — should be included (>= semantics)
        XCTAssertEqual(SubscriptionStateMachine.activeSessionCount(
            uploadedTimestamps: [windowStart], from: now, calendar: cal), 1,
            "Session exactly at the 30-day window start must be included (inclusive boundary)")
    }

    func testSessionOneSecondBeforeWindowStart_notCounted() {
        let now = date("2024-06-01T00:00:00Z")
        let justOutside = cal.date(byAdding: .day, value: -30, to: now)!.addingTimeInterval(-1)
        XCTAssertEqual(SubscriptionStateMachine.activeSessionCount(
            uploadedTimestamps: [justOutside], from: now, calendar: cal), 0,
            "Session 1 second before the 30-day window must not be counted")
    }

    func testSessionOneSecondAfterWindowStart_counted() {
        let now = date("2024-06-01T00:00:00Z")
        let justInside = cal.date(byAdding: .day, value: -30, to: now)!.addingTimeInterval(1)
        XCTAssertEqual(SubscriptionStateMachine.activeSessionCount(
            uploadedTimestamps: [justInside], from: now, calendar: cal), 1,
            "Session 1 second after the 30-day window start must count")
    }

    // MARK: - Device clock behind (lenient threshold — expected / documented behaviour)

    func testClockBehind_oldSessionAppearsInWindow() {
        // Device clock is 3 days behind reality.
        // A session 31 days ago (reality) appears only 28 days ago from device's perspective.
        // Expected: session counts on the slow device (lenient threshold — not a bug, documented).
        let realNow   = date("2024-06-01T00:00:00Z")
        let deviceNow = date("2024-05-29T00:00:00Z") // 3 days behind
        let session   = date("2024-05-01T00:00:00Z") // 31 days before realNow, 28 days before deviceNow

        let deviceCount = SubscriptionStateMachine.activeSessionCount(
            uploadedTimestamps: [session, session, session],
            from: deviceNow, calendar: cal)
        XCTAssertEqual(deviceCount, 3,
            "Behind-clock device sees this session as 28 days old (inside window) — lenient but expected")

        let realCount = SubscriptionStateMachine.activeSessionCount(
            uploadedTimestamps: [session, session, session],
            from: realNow, calendar: cal)
        XCTAssertEqual(realCount, 0,
            "Real time: same sessions are 31 days old (outside window)")
    }

    func testClockBehind_doesNotGrantPermanentAccess() {
        // Even 1000 days behind, an old session eventually falls outside the window
        let now = date("2020-01-01T00:00:00Z") // device stuck in 2020
        let session = date("2019-01-01T00:00:00Z") // over a year before even the slow clock
        XCTAssertEqual(SubscriptionStateMachine.activeSessionCount(
            uploadedTimestamps: [session, session, session], from: now, calendar: cal), 0,
            "Even a behind-clock device can't grant permanent access — old sessions expire")
    }

    // MARK: - Mixed scenarios

    func testMixed_twoInWindow_oneJustOutside_belowThreshold() {
        let now = date("2024-06-01T12:00:00Z")
        let session1 = date("2024-05-20T10:00:00Z") // 12 days ago — in
        let session2 = date("2024-05-15T10:00:00Z") // 17 days ago — in
        let session3 = date("2024-04-30T10:00:00Z") // 32 days ago — out
        XCTAssertEqual(
            SubscriptionStateMachine.activeSessionCount(
                uploadedTimestamps: [session1, session2, session3], from: now, calendar: cal), 2,
            "2 in-window + 1 just outside = count 2")
        XCTAssertFalse(
            SubscriptionStateMachine.isActivelyConnected(
                uploadedTimestamps: [session1, session2, session3], from: now, calendar: cal),
            "Count 2 < threshold 3 → not actively connected → lapsed")
    }

    func testMixed_twoInWindow_oneFuture_belowThreshold() {
        // Clock-manipulation attempt: 2 real sessions + 1 future-dated session
        // Must still be below threshold (future doesn't count)
        let now = date("2024-06-01T12:00:00Z")
        let real1 = date("2024-05-20T10:00:00Z")
        let real2 = date("2024-05-15T10:00:00Z")
        let cheat = date("2024-06-15T00:00:00Z") // future-dated cheat session
        XCTAssertFalse(
            SubscriptionStateMachine.isActivelyConnected(
                uploadedTimestamps: [real1, real2, cheat], from: now, calendar: cal),
            "Future-dated session must not allow gaming the threshold (2 real + 1 future = 2 < 3)")
    }

    // MARK: - Rapid within-day state transitions

    func testRapidTransitions_connectedLapsedConnectedSameDay() {
        let now = date("2024-06-01T18:00:00Z")

        // Morning: 3 sessions uploaded → connected
        let morningSessions = [
            date("2024-05-20T09:00:00Z"),
            date("2024-05-18T09:00:00Z"),
            date("2024-05-16T09:00:00Z"),
        ]
        XCTAssertTrue(SubscriptionStateMachine.isActivelyConnected(
            uploadedTimestamps: morningSessions, from: now, calendar: cal))

        // Midday state: one session falls just outside (simulate window moving forward slightly)
        let noonCheck = date("2024-06-01T12:00:00Z")
        // Same sessions, slightly different now (still all in window)
        XCTAssertTrue(SubscriptionStateMachine.isActivelyConnected(
            uploadedTimestamps: morningSessions, from: noonCheck, calendar: cal))

        // Evening: simulate 2 sessions deleted → only 2 remain → lapsed
        let twoRemaining = Array(morningSessions.prefix(2))
        XCTAssertFalse(SubscriptionStateMachine.isActivelyConnected(
            uploadedTimestamps: twoRemaining, from: now, calendar: cal),
            "After dropping to 2 sessions, should lapse")

        // Evening re-upload: 3rd session added back → connected again
        let threeAgain = twoRemaining + [date("2024-05-14T09:00:00Z")]
        XCTAssertTrue(SubscriptionStateMachine.isActivelyConnected(
            uploadedTimestamps: threeAgain, from: now, calendar: cal),
            "After re-uploading 3rd session, should be connected again")
    }

    func testRapidStateTransitions_viaStateMachine() {
        // Models within-day event sequence as state machine transitions
        var state: SubscriptionState = .connected

        // Session upload → still connected
        state = SubscriptionStateMachine.transition(from: state, event: .activeConnectionAchieved)
        XCTAssertEqual(state, .connected)

        // Drop below threshold
        state = SubscriptionStateMachine.transition(from: state, event: .connectionLapsed)
        XCTAssertEqual(state, .expired)

        // Upload more sessions → connected
        state = SubscriptionStateMachine.transition(from: state, event: .activeConnectionAchieved)
        XCTAssertEqual(state, .connected)

        // Another lapse attempt
        state = SubscriptionStateMachine.transition(from: state, event: .connectionLapsed)
        XCTAssertEqual(state, .expired)

        // Subscribe → subscribed (all thresholds bypassed)
        state = SubscriptionStateMachine.transition(from: state, event: .purchased)
        XCTAssertEqual(state, .subscribed)
    }

    // MARK: - Determinism: same input always produces same output

    func testActiveSessionCount_deterministic() {
        let now = date("2024-06-01T00:00:00Z")
        let timestamps = [
            date("2024-05-20T10:00:00Z"),
            date("2024-05-03T10:00:00Z"),
            date("2024-04-30T10:00:00Z"), // outside
            date("2024-06-05T00:00:00Z"), // future
        ]
        let expected = 2 // only the two in-window past sessions count
        for _ in 0..<20 {
            XCTAssertEqual(
                SubscriptionStateMachine.activeSessionCount(
                    uploadedTimestamps: timestamps, from: now, calendar: cal),
                expected,
                "activeSessionCount must be deterministic across repeated calls")
        }
    }
}
