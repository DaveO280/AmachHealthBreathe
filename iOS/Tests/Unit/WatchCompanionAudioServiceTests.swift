import XCTest
@testable import AmachBreathe
import AmachBreatheShared

@MainActor
final class WatchCompanionAudioServiceTests: XCTestCase {

    func testTakeMetricsForMerge_isIdempotent() {
        let service = WatchCompanionAudioService()
        service.armForPhoneInitiatedWatchStart(
            sessionId: "session-a",
            bpm: 5.5,
            companionEnabled: true
        )
        _ = service.takeMetricsForMerge(sessionId: "session-a")
        XCTAssertNil(service.takeMetricsForMerge(sessionId: "session-a"))
    }

    func testHandleSessionStarted_respectsSettingsOff() async {
        let service = WatchCompanionAudioService()
        service.setCompanionEnabledInSettings(false)
        service.handleSessionStarted(SessionStartedMessage(
            sessionId: "solo",
            bpm: 5.5,
            durationSeconds: 300,
            ratio: "4:6"
        ))
        XCTAssertNil(service.takeMetricsForMerge(sessionId: "solo"))
    }

    func testPhaseHint_ignoredForWrongSession() {
        let service = WatchCompanionAudioService()
        service.handlePhaseHint(SessionPhaseHintMessage(sessionId: "other", phase: .mainStarted))
        // No crash; active session unchanged
        XCTAssertNil(service.takeMetricsForMerge(sessionId: "other"))
    }
}
