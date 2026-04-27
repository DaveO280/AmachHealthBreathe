import XCTest
@testable import AmachBreatheShared

final class ComplicationStateTests: XCTestCase {

    // MARK: - ComplicationState derivation

    func testInSessionTrumpsEverything() {
        XCTAssertEqual(
            ComplicationDisplayLogic.complicationState(inSession: true, hasCalibration: false),
            .inSession)
        XCTAssertEqual(
            ComplicationDisplayLogic.complicationState(inSession: true, hasCalibration: true),
            .inSession)
    }

    func testReadyWhenCalibrated() {
        XCTAssertEqual(
            ComplicationDisplayLogic.complicationState(inSession: false, hasCalibration: true),
            .ready)
    }

    func testIdleWhenNotCalibratedAndNotInSession() {
        XCTAssertEqual(
            ComplicationDisplayLogic.complicationState(inSession: false, hasCalibration: false),
            .idle)
    }

    // MARK: - DisplayInfo — inSession state

    func testInSessionDisplayInfo() {
        let info = ComplicationDisplayLogic.displayInfo(
            complicationState: .inSession, subscriptionState: .trial)
        XCTAssertEqual(info.iconName, "lungs.fill")
        XCTAssertEqual(info.label, "Active")
    }

    func testInSessionSameAcrossAllSubscriptionStates() {
        for sub in SubscriptionState.allCases {
            let info = ComplicationDisplayLogic.displayInfo(
                complicationState: .inSession, subscriptionState: sub)
            XCTAssertEqual(info.iconName, "lungs.fill", "Failed for subscription: \(sub)")
        }
    }

    // MARK: - DisplayInfo — ready state

    func testReadyDisplayInfo() {
        let info = ComplicationDisplayLogic.displayInfo(
            complicationState: .ready, subscriptionState: .subscribed)
        XCTAssertEqual(info.iconName, "waveform.path.ecg.rectangle")
        XCTAssertEqual(info.label, "Breathe")
    }

    func testReadySameAcrossAllSubscriptionStates() {
        for sub in SubscriptionState.allCases {
            let info = ComplicationDisplayLogic.displayInfo(
                complicationState: .ready, subscriptionState: sub)
            XCTAssertEqual(info.iconName, "waveform.path.ecg.rectangle", "Failed for subscription: \(sub)")
            XCTAssertEqual(info.label, "Breathe", "Failed for subscription: \(sub)")
        }
    }

    // MARK: - DisplayInfo — idle state

    func testIdleExpiredSubscription() {
        let info = ComplicationDisplayLogic.displayInfo(
            complicationState: .idle, subscriptionState: .expired)
        XCTAssertEqual(info.iconName, "exclamationmark.circle")
        XCTAssertEqual(info.label, "Expired")
    }

    func testIdleTrialSubscription() {
        let info = ComplicationDisplayLogic.displayInfo(
            complicationState: .idle, subscriptionState: .trial)
        XCTAssertEqual(info.iconName, "waveform.path.ecg")
        XCTAssertEqual(info.label, "Setup")
    }

    func testIdleConnectedSubscription() {
        let info = ComplicationDisplayLogic.displayInfo(
            complicationState: .idle, subscriptionState: .connected)
        XCTAssertEqual(info.label, "Setup")
    }

    func testIdleSubscribedSubscription() {
        let info = ComplicationDisplayLogic.displayInfo(
            complicationState: .idle, subscriptionState: .subscribed)
        XCTAssertEqual(info.label, "Setup")
    }

    // MARK: - Color hex values

    func testInSessionAccentColorIsGreen() {
        let info = ComplicationDisplayLogic.displayInfo(
            complicationState: .inSession, subscriptionState: .trial)
        XCTAssertEqual(info.accentColorHex, "10B981")
    }

    func testReadyAccentColorIsPrimary() {
        let info = ComplicationDisplayLogic.displayInfo(
            complicationState: .ready, subscriptionState: .trial)
        XCTAssertEqual(info.accentColorHex, "6366F1")
    }

    func testExpiredAccentColorIsRed() {
        let info = ComplicationDisplayLogic.displayInfo(
            complicationState: .idle, subscriptionState: .expired)
        XCTAssertEqual(info.accentColorHex, "EF4444")
    }

    // MARK: - UserDefaults key constants

    func testKeyConstantsAreUnique() {
        let keys: Set<String> = [
            ComplicationDisplayLogic.inSessionKey,
            ComplicationDisplayLogic.hasCalibrationKey,
            ComplicationDisplayLogic.subscriptionKey
        ]
        XCTAssertEqual(keys.count, 3)
    }

    // MARK: - CaseIterable coverage

    func testDisplayInfoCoversAllComplicationStates() {
        for state in ComplicationState.allCases {
            for sub in SubscriptionState.allCases {
                let info = ComplicationDisplayLogic.displayInfo(
                    complicationState: state, subscriptionState: sub)
                XCTAssertFalse(info.iconName.isEmpty, "Missing icon for \(state), \(sub)")
                XCTAssertFalse(info.label.isEmpty, "Missing label for \(state), \(sub)")
                XCTAssertFalse(info.accentColorHex.isEmpty, "Missing color for \(state), \(sub)")
            }
        }
    }
}

// Add CaseIterable to SubscriptionState for exhaustive test coverage
extension SubscriptionState: CaseIterable {
    public static var allCases: [SubscriptionState] { [.trial, .subscribed, .connected, .expired] }
}
