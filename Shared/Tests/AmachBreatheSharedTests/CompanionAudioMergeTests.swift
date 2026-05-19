import XCTest
@testable import AmachBreatheShared

final class CompanionAudioMergeTests: XCTestCase {

    func testMergingCompanionAudioMetrics_attachesWhenAbsent() {
        let watchRecord = BreathingSessionRecord(
            id: "session-1",
            timestamp: Date(),
            durationSeconds: 300,
            bpm: 5.5,
            ratio: "4:6",
            baselineHRV: 40,
            coherenceScore: 0.8,
            source: .watch
        )
        let metrics = AudioBreathMetrics(
            enabled: true,
            permissionGranted: true,
            targetBreathingBPM: 5.5,
            estimatedBreathingBPM: 5.4,
            confidence: 0.7,
            dataQuality: .good
        )

        let merged = watchRecord.mergingCompanionAudioMetrics(metrics)
        XCTAssertEqual(merged.audioBreathMetrics, metrics)
        XCTAssertEqual(merged.source, .watch)
        XCTAssertEqual(merged.id, watchRecord.id)
    }

    func testMergingCompanionAudioMetrics_idempotentWhenAlreadyPresent() {
        let existing = AudioBreathMetrics(
            enabled: true,
            permissionGranted: true,
            targetBreathingBPM: 5.5
        )
        let watchRecord = BreathingSessionRecord(
            id: "session-1",
            timestamp: Date(),
            durationSeconds: 300,
            bpm: 5.5,
            ratio: "4:6",
            source: .watch,
            audioBreathMetrics: existing
        )
        let phoneMetrics = AudioBreathMetrics(
            enabled: true,
            permissionGranted: true,
            targetBreathingBPM: 6.0
        )

        let merged = watchRecord.mergingCompanionAudioMetrics(phoneMetrics)
        XCTAssertEqual(merged.audioBreathMetrics, existing)
    }

    func testMergingCompanionAudioMetrics_nilMetricsReturnsSelf() {
        let watchRecord = BreathingSessionRecord(
            id: "session-1",
            timestamp: Date(),
            durationSeconds: 300,
            bpm: 5.5,
            ratio: "4:6",
            source: .watch
        )
        XCTAssertEqual(watchRecord.mergingCompanionAudioMetrics(nil).id, watchRecord.id)
        XCTAssertNil(watchRecord.mergingCompanionAudioMetrics(nil).audioBreathMetrics)
    }
}
