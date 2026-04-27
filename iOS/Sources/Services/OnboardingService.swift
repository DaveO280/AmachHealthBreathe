import Foundation
import AmachBreatheShared

/// Tracks whether the user has completed first-launch onboarding.
/// Writes are made by the view on completion; this service only tracks state.
@MainActor
public final class OnboardingService: ObservableObject {

    public static let userDefaultsKey = "com.amach.breathe.hasCompletedOnboarding"

    @Published public private(set) var hasCompletedOnboarding: Bool

    public init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.userDefaultsKey)
    }

    public func markComplete() {
        UserDefaults.standard.set(true, forKey: Self.userDefaultsKey)
        hasCompletedOnboarding = true
    }

    /// Only used in tests / dev; safe to call repeatedly.
    public func reset() {
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
        hasCompletedOnboarding = false
    }
}
