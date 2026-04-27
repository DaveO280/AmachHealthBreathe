import Foundation
import UserNotifications
import AmachBreatheShared

@MainActor
public final class NotificationService: ObservableObject {

    public static let shared = NotificationService()

    @Published public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {}

    // MARK: - Authorization

    public func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            return false
        }
    }

    public func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    // MARK: - Scheduling

    /// Cancel existing reminders and schedule new ones.
    /// Caps at NotificationScheduler.maxRemindersPerDay (2). Uses daily repeat with current TZ.
    public func scheduleReminders(_ secondsFromMidnight: [Int]) async {
        let capped = NotificationScheduler.cappedReminders(secondsFromMidnight)
        let center = UNUserNotificationCenter.current()

        // Cancel all existing reminders first
        let existing = capped.map { NotificationScheduler.notificationIdentifier(secondsFromMidnight: $0) }
        let allIDs = await center.pendingNotificationRequests().map { $0.identifier }
        let toRemove = allIDs.filter { $0.hasPrefix("com.amach.breathe.reminder.") && !existing.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        for seconds in capped {
            let id = NotificationScheduler.notificationIdentifier(secondsFromMidnight: seconds)
            let content = UNMutableNotificationContent()
            content.title = "Time to Breathe"
            content.body  = "Your daily resonant breathing session is ready."
            content.sound = .default

            let components = NotificationScheduler.dateComponents(secondsFromMidnight: seconds)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

            try? await center.add(request)
        }
    }

    public func cancelAllReminders() {
        let center = UNUserNotificationCenter.current()
        Task {
            let ids = await center.pendingNotificationRequests()
                .map { $0.identifier }
                .filter { $0.hasPrefix("com.amach.breathe.reminder.") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}
