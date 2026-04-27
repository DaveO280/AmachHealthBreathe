import XCTest
@testable import AmachBreathe
import AmachBreatheShared

/// Stress tests for WatchConnectivity queue delivery and session deduplication.
///
/// WCSession's store-and-forward behaviour is tested at the application layer:
///   - SessionService.save() is the idempotent delivery gate
///   - SessionHistoryModel.rows() provides the sorted, display-ready view
///
/// Invariants asserted:
///   - A session delivered twice is stored exactly once (no double-write)
///   - All offline-queued sessions are saved when the batch arrives
///   - Sessions sort newest-first in the history view regardless of delivery order
///   - A full reconnect burst (N duplicates) never inflates the count
@MainActor
final class WatchQueueDeliveryTests: XCTestCase {

    private let storageKey = "com.amach.breathe.sessions"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeRecord(
        id: String,
        secondsAgo: TimeInterval = 0,
        duration: Int = 300
    ) -> BreathingSessionRecord {
        BreathingSessionRecord(
            id: id,
            timestamp: Date().addingTimeInterval(-secondsAgo),
            durationSeconds: duration,
            bpm: 5.5, ratio: "4:6",
            baselineHRV: 50, recoveryHRV: 58, avgHRV: 54,
            coherenceScore: 0.8, reflectionRating: nil
        )
    }

    private func freshService() -> SessionService {
        // Each call creates a fresh service reading the (cleared) UserDefaults
        SessionService()
    }

    // MARK: - 1. Duplicate delivery: same session ID received twice

    func testDuplicate_sameRecord_storedOnce() {
        let service = freshService()
        let record = makeRecord(id: "dup-001")
        service.save(record)
        service.save(record)
        XCTAssertEqual(service.sessions.count, 1,
            "Identical session delivered twice must be stored exactly once")
    }

    func testDuplicate_sameIDDifferentContent_firstWins() {
        // Models retransmission where payload differs slightly (e.g. different coherenceScore)
        let service = freshService()
        let first  = makeRecord(id: "dup-002", duration: 300)
        let second = makeRecord(id: "dup-002", duration: 600) // different duration, same ID
        service.save(first)
        service.save(second)
        XCTAssertEqual(service.sessions.count, 1)
        XCTAssertEqual(service.sessions[0].breathingSession.durationSeconds, 300,
            "First delivery wins — retransmission must not overwrite an already-stored session")
    }

    func testDuplicate_threeDeliveries_storedOnce() {
        let service = freshService()
        let record = makeRecord(id: "dup-003")
        service.save(record)
        service.save(record)
        service.save(record)
        XCTAssertEqual(service.sessions.count, 1)
    }

    // MARK: - 2. Multiple offline sessions delivered on reconnect

    func testOfflineQueue_fiveSessions_allStored() {
        let service = freshService()
        let records = (1...5).map { makeRecord(id: "offline-\($0)", secondsAgo: Double($0) * 3600) }
        for r in records { service.save(r) }
        XCTAssertEqual(service.sessions.count, 5,
            "All 5 offline sessions must be stored on reconnect")
    }

    func testOfflineQueue_tenSessions_allStoredNoDuplicates() {
        let service = freshService()
        let records = (1...10).map { makeRecord(id: "queue-\($0)") }
        for r in records { service.save(r) }
        XCTAssertEqual(service.sessions.count, 10)
    }

    func testOfflineQueue_reconnectBurst_duplicatesFiltered() {
        // WCSession may redeliver queued messages after reconnect.
        // Simulate: 4 sessions, each delivered twice in a reconnect burst.
        let service = freshService()
        let records = (1...4).map { makeRecord(id: "burst-\($0)", secondsAgo: Double($0) * 1800) }

        // First batch (initial delivery)
        for r in records { service.save(r) }
        // Second batch (reconnect retransmission)
        for r in records { service.save(r) }

        XCTAssertEqual(service.sessions.count, 4,
            "Reconnect duplicate burst must not inflate the stored count")
    }

    // MARK: - 3. Ordering: sessions sort newest-first in history view

    func testHistoryView_sortedNewestFirst() {
        let service = freshService()
        let now = Date()
        // Deliver sessions oldest-first (simulates FIFO queue from Watch)
        let records = (0..<5).map { i in
            makeRecord(id: "order-\(i)", secondsAgo: Double(4 - i) * 3600) // oldest first
        }
        for r in records { service.save(r) }

        let rows = SessionHistoryModel.rows(from: service.sessions.map(\.breathingSession))
        let timestamps = rows.map { $0.timestamp }
        let sorted = timestamps.sorted(by: >)
        XCTAssertEqual(timestamps, sorted,
            "SessionHistoryModel.rows must return sessions sorted newest-first")
    }

    func testHistoryView_fifoDelivery_orderIndependent() {
        // Regardless of delivery order, the history view must always be newest-first
        let service = freshService()
        let now = Date()
        // Deliver in random order
        let ids   = ["c", "a", "e", "b", "d"]
        let ages  = [1.0, 5.0, 2.0, 4.0, 3.0] // hours ago
        for (id, age) in zip(ids, ages) {
            service.save(makeRecord(id: id, secondsAgo: age * 3600))
        }

        let rows = SessionHistoryModel.rows(from: service.sessions.map(\.breathingSession))
        let timestamps = rows.map { $0.timestamp }
        XCTAssertEqual(timestamps, timestamps.sorted(by: >),
            "History view must be newest-first regardless of delivery order")
    }

    // MARK: - 4. Watch reconnects after Power Reserve — queued records correct order

    func testPowerReserve_multipleCompletedOffline_allPresent() {
        // Watch completed 3 sessions while in Power Reserve mode.
        // On reconnect they arrive in completion order.
        let service = freshService()
        let session1 = makeRecord(id: "pr-1", secondsAgo: 3600, duration: 900)
        let session2 = makeRecord(id: "pr-2", secondsAgo: 2400, duration: 600)
        let session3 = makeRecord(id: "pr-3", secondsAgo: 1200, duration: 300)

        // Delivered in completion order (oldest first, FIFO)
        service.save(session1)
        service.save(session2)
        service.save(session3)

        XCTAssertEqual(service.sessions.count, 3)
        let ids = Set(service.sessions.map(\.id))
        XCTAssertTrue(ids.contains("pr-1"))
        XCTAssertTrue(ids.contains("pr-2"))
        XCTAssertTrue(ids.contains("pr-3"))
    }

    func testPowerReserve_reconnectResendsAll_noDuplicates() {
        let service = freshService()
        let records = ["pr-x1", "pr-x2", "pr-x3"].map { makeRecord(id: $0) }

        // First delivery
        for r in records { service.save(r) }
        // WCSession resends on reconnect
        for r in records { service.save(r) }

        XCTAssertEqual(service.sessions.count, 3,
            "Power Reserve reconnect resend must not duplicate sessions")
    }

    // MARK: - 5. Persistence across service instances (simulates app restart after reconnect)

    func testPersistence_sessionsReloadAfterRestart() {
        // Save sessions in one service instance
        let service1 = freshService()
        let records = (1...3).map { makeRecord(id: "persist-\($0)") }
        for r in records { service1.save(r) }

        // Simulate app restart — new service instance reads from disk
        let service2 = SessionService()
        XCTAssertEqual(service2.sessions.count, 3,
            "Sessions must survive app restart (persisted to UserDefaults)")
    }

    func testPersistence_duplicateOnRestart_stillIdempotent() {
        // First run: save 3 sessions
        let service1 = freshService()
        let records = (1...3).map { makeRecord(id: "restart-\($0)") }
        for r in records { service1.save(r) }

        // After restart, WCSession redelivers same messages
        let service2 = SessionService()
        for r in records { service2.save(r) }

        XCTAssertEqual(service2.sessions.count, 3,
            "Post-restart duplicate delivery must remain idempotent")
    }
}
