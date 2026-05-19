import XCTest
@testable import AmachBreathe
import AmachBreatheShared

@MainActor
final class SessionServiceTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SessionServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDeleteSessionRemovesRecordAndPersists() {
        let storageKey = "sessions"
        let service = SessionService(userDefaults: defaults, storageKey: storageKey)
        let first = makeRecord(id: "first")
        let second = makeRecord(id: "second")

        service.save(first)
        service.save(second)
        service.deleteSession(id: "first")

        XCTAssertEqual(service.sessions.map(\.id), ["second"])

        let reloaded = SessionService(userDefaults: defaults, storageKey: storageKey)
        XCTAssertEqual(reloaded.sessions.map(\.id), ["second"])
    }

    func testDeleteMissingSessionIsNoOp() {
        let service = SessionService(userDefaults: defaults, storageKey: "sessions")
        let record = makeRecord(id: "existing")

        service.save(record)
        service.deleteSession(id: "missing")

        XCTAssertEqual(service.sessions.map(\.id), ["existing"])
    }

    func testCoachingThreadPersistsAcrossReload() {
        let storageKey = "sessions.coaching"
        let service = SessionService(userDefaults: defaults, storageKey: storageKey)
        let record = makeRecord(id: "coach-session")
        service.save(record)

        let coaching = SessionCoachingState(
            messages: [
                .user("Summarize my session"),
                .assistant("You held a steady rhythm.")
            ],
            lastInsight: CoachingInsight(content: "You held a steady rhythm.")
        )
        service.updateCoaching(forSessionId: "coach-session", coaching: coaching)

        let reloaded = SessionService(userDefaults: defaults, storageKey: storageKey)
        XCTAssertEqual(reloaded.coachingState(forSessionId: "coach-session"), coaching)
    }

    private func makeRecord(id: String) -> BreathingSessionRecord {
        BreathingSessionRecord(
            id: id,
            timestamp: Date(),
            durationSeconds: 300,
            bpm: 5.5,
            ratio: "4:6",
            baselineHRV: 50,
            recoveryHRV: 55,
            avgHRV: 53,
            coherenceScore: 0.72,
            source: .watch
        )
    }
}
