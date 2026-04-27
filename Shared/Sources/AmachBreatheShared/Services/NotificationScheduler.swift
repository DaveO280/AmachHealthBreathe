import Foundation

/// Pure scheduling logic — converts seconds-from-midnight settings to calendar triggers.
/// Platform-independent; tested in macOS Shared test suite.
public enum NotificationScheduler {

    public static let maxRemindersPerDay = 2

    /// Caps and sorts reminder times (earliest first, at most `maxRemindersPerDay`).
    public static func cappedReminders(_ seconds: [Int]) -> [Int] {
        Array(seconds.filter { isValid($0) }.sorted().prefix(maxRemindersPerDay))
    }

    /// Returns `DateComponents` suitable for a `UNCalendarNotificationTrigger`.
    /// Hour and minute are derived from `secondsFromMidnight` in the given timezone.
    public static func dateComponents(
        secondsFromMidnight: Int,
        timeZone: TimeZone = .current
    ) -> DateComponents {
        let hours   = (secondsFromMidnight / 3600) % 24
        let minutes = (secondsFromMidnight % 3600) / 60
        return DateComponents(timeZone: timeZone, hour: hours, minute: minutes)
    }

    /// Stable identifier for a reminder at a given time.
    public static func notificationIdentifier(secondsFromMidnight: Int) -> String {
        "com.amach.breathe.reminder.\(secondsFromMidnight)"
    }

    /// A seconds value is valid if it falls within a single calendar day.
    public static func isValid(_ secondsFromMidnight: Int) -> Bool {
        secondsFromMidnight >= 0 && secondsFromMidnight < 86400
    }

    /// Human-readable time string for display (e.g. "8:00 AM").
    public static func displayTime(secondsFromMidnight: Int) -> String {
        var components = DateComponents()
        components.hour   = (secondsFromMidnight / 3600) % 24
        components.minute = (secondsFromMidnight % 3600) / 60
        let cal = Calendar.current
        guard let date = cal.date(from: components) else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
