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

    // MARK: - Key format

    func testOnboardingServiceKeyFormat() {
        XCTAssertTrue(OnboardingService.userDefaultsKey.hasPrefix("com.amach.breathe."))
        XCTAssertFalse(OnboardingService.userDefaultsKey.isEmpty)
    }
}
