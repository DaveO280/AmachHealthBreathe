import XCTest
@testable import AmachBreatheShared

final class NotificationSchedulingTests: XCTestCase {

    // MARK: - dateComponents

    func testDateComponentsForMidnight() {
        let comps = NotificationScheduler.dateComponents(secondsFromMidnight: 0)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
    }

    func testDateComponentsFor8AM() {
        let comps = NotificationScheduler.dateComponents(secondsFromMidnight: 8 * 3600)
        XCTAssertEqual(comps.hour, 8)
        XCTAssertEqual(comps.minute, 0)
    }

    func testDateComponentsFor6PM() {
        let comps = NotificationScheduler.dateComponents(secondsFromMidnight: 18 * 3600)
        XCTAssertEqual(comps.hour, 18)
        XCTAssertEqual(comps.minute, 0)
    }

    func testDateComponentsFor8h30m() {
        let comps = NotificationScheduler.dateComponents(secondsFromMidnight: 8 * 3600 + 30 * 60)
        XCTAssertEqual(comps.hour, 8)
        XCTAssertEqual(comps.minute, 30)
    }

    func testDateComponentsAtEndOfDay() {
        let comps = NotificationScheduler.dateComponents(secondsFromMidnight: 23 * 3600 + 59 * 60)
        XCTAssertEqual(comps.hour, 23)
        XCTAssertEqual(comps.minute, 59)
    }

    func testDateComponentsIncludesTimezone() {
        let utc = TimeZone(secondsFromGMT: 0)!         // equivalent to UTC/GMT
        let est = TimeZone(identifier: "America/New_York")!
        let compsUTC = NotificationScheduler.dateComponents(secondsFromMidnight: 3600, timeZone: utc)
        let compsEST = NotificationScheduler.dateComponents(secondsFromMidnight: 3600, timeZone: est)
        // Same clock time (1:00 AM) but different timezones
        XCTAssertEqual(compsUTC.hour, 1)
        XCTAssertEqual(compsEST.hour, 1)
        XCTAssertEqual(compsUTC.timeZone?.secondsFromGMT(), 0)
        XCTAssertEqual(compsEST.timeZone?.identifier, "America/New_York")
    }

    // MARK: - cappedReminders

    func testCappedRemindersReturnsSorted() {
        let result = NotificationScheduler.cappedReminders([64800, 28800])  // 6pm, 8am
        XCTAssertEqual(result, [28800, 64800])
    }

    func testCappedRemindersAtMax() {
        let result = NotificationScheduler.cappedReminders([28800, 43200, 64800])  // 8am, 12pm, 6pm
        XCTAssertEqual(result.count, NotificationScheduler.maxRemindersPerDay)
    }

    func testCappedRemindersEmpty() {
        XCTAssertEqual(NotificationScheduler.cappedReminders([]), [])
    }

    func testCappedRemindersFiltersInvalid() {
        let result = NotificationScheduler.cappedReminders([-1, 28800, 86400])  // -1 and 86400 are invalid
        XCTAssertEqual(result, [28800])
    }

    func testCappedRemindersMaxIs2() {
        XCTAssertEqual(NotificationScheduler.maxRemindersPerDay, 2)
    }

    // MARK: - notificationIdentifier

    func testIdentifierFormat() {
        let id = NotificationScheduler.notificationIdentifier(secondsFromMidnight: 28800)
        XCTAssertEqual(id, "com.amach.breathe.reminder.28800")
    }

    func testIdentifierUnique() {
        let id1 = NotificationScheduler.notificationIdentifier(secondsFromMidnight: 28800)
        let id2 = NotificationScheduler.notificationIdentifier(secondsFromMidnight: 64800)
        XCTAssertNotEqual(id1, id2)
    }

    func testIdentifierHasPrefix() {
        let id = NotificationScheduler.notificationIdentifier(secondsFromMidnight: 0)
        XCTAssertTrue(id.hasPrefix("com.amach.breathe.reminder."))
    }

    // MARK: - isValid

    func testIsValidMidnight() {
        XCTAssertTrue(NotificationScheduler.isValid(0))
    }

    func testIsValidEndOfDay() {
        XCTAssertTrue(NotificationScheduler.isValid(86399))
    }

    func testIsInvalidNegative() {
        XCTAssertFalse(NotificationScheduler.isValid(-1))
    }

    func testIsInvalidMidnightNext() {
        XCTAssertFalse(NotificationScheduler.isValid(86400))
    }

    func testIsInvalidLarge() {
        XCTAssertFalse(NotificationScheduler.isValid(100000))
    }

    // MARK: - Daily repeat implied by trigger (verified via components)

    func testDailyRepeatTriggerStructure() {
        // Verify that the DateComponents we produce are suitable for a daily repeating trigger.
        // A UNCalendarNotificationTrigger with repeats=true fires every day at the specified H:M.
        let comps = NotificationScheduler.dateComponents(secondsFromMidnight: 9 * 3600)
        // Only hour and minute should be set (not year/month/day) so it repeats daily
        XCTAssertNil(comps.year)
        XCTAssertNil(comps.month)
        XCTAssertNil(comps.day)
        XCTAssertNotNil(comps.hour)
        XCTAssertNotNil(comps.minute)
    }
}
