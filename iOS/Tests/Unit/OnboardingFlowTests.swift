import XCTest
@testable import AmachBreathe
import AmachBreatheShared

@MainActor
final class OnboardingFlowTests: XCTestCase {

    private let testKey = OnboardingService.userDefaultsKey

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    // MARK: - OnboardingService state tracking

    func testFirstLaunchShowsOnboarding() {
        UserDefaults.standard.removeObject(forKey: testKey)
        let service = OnboardingService()
        XCTAssertFalse(service.hasCompletedOnboarding)
    }

    func testMarkCompleteUpdatesState() {
        let service = OnboardingService()
        XCTAssertFalse(service.hasCompletedOnboarding)
        service.markComplete()
        XCTAssertTrue(service.hasCompletedOnboarding)
    }

    func testMarkCompletePersistsToDisk() {
        let service = OnboardingService()
        service.markComplete()
        // Simulate app restart: read persisted value
        let freshService = OnboardingService()
        XCTAssertTrue(freshService.hasCompletedOnboarding)
    }

    func testResetClearsState() {
        let service = OnboardingService()
        service.markComplete()
        XCTAssertTrue(service.hasCompletedOnboarding)
        service.reset()
        XCTAssertFalse(service.hasCompletedOnboarding)
    }

    func testResetClearsPersistedValue() {
        let service = OnboardingService()
        service.markComplete()
        service.reset()
        let freshService = OnboardingService()
        XCTAssertFalse(freshService.hasCompletedOnboarding)
    }

    // MARK: - AppSettings written on completion

    func testOnboardingWritesDefaultRatio() {
        let settings = AppSettingsService()
        settings.updateRatio(.oneToOne)
        XCTAssertEqual(settings.settings.defaultRatio, .oneToOne)
        settings.updateRatio(.fourToSix)
        XCTAssertEqual(settings.settings.defaultRatio, .fourToSix)
    }

    func testOnboardingWritesReminderTimes() {
        let settings = AppSettingsService()
        let times = [28800, 64800]  // 8am, 6pm
        settings.updateReminders(times)
        XCTAssertEqual(settings.settings.reminderSecondsFromMidnight, times)
    }

    func testOnboardingReminderTimesRoundTrip() throws {
        let settings = AppSettingsService()
        let times = [8 * 3600, 18 * 3600]
        settings.updateReminders(times)
        // Simulate restart: create new instance (reads from UserDefaults)
        let fresh = AppSettingsService()
        XCTAssertEqual(fresh.settings.reminderSecondsFromMidnight, times)
    }

    func testOnboardingClearsRemindersWhenEmpty() {
        let settings = AppSettingsService()
        settings.updateReminders([28800])
        settings.updateReminders([])
        XCTAssertTrue(settings.settings.reminderSecondsFromMidnight.isEmpty)
    }

    // MARK: - Privacy: notification permission key

    func testOnboardingServiceKeyFormat() {
        XCTAssertTrue(OnboardingService.userDefaultsKey.hasPrefix("com.amach.breathe."))
        XCTAssertFalse(OnboardingService.userDefaultsKey.isEmpty)
    }
}
