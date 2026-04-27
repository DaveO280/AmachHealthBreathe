import XCTest
@testable import AmachBreatheShared

final class TrendEngineTests: XCTestCase {

    // MARK: - Fixture helpers

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ offset: Int, from base: Date) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: base))!
    }

    /// Returns a session at a given date with configurable metrics.
    private func session(
        daysAgo: Int,
        base: Date,
        bpm: Double = 6.0,
        coherence: Double = 0.7,
        hrv: Double = 55.0,
        duration: Int = 300
    ) -> BreathingSessionRecord {
        BreathingSessionRecord(
            id: UUID().uuidString,
            timestamp: day(-daysAgo, from: base),
            durationSeconds: duration,
            bpm: bpm,
            ratio: "4:6",
            baselineHRV: hrv,
            recoveryHRV: hrv + 5,
            avgHRV: hrv,
            coherenceScore: coherence,
            reflectionRating: nil
        )
    }

    /// Builds `count` sessions spread evenly over the last `count` days.
    private func makeSessions(_ count: Int, base: Date = Date()) -> [BreathingSessionRecord] {
        (0..<count).map { i in session(daysAgo: i, base: base) }
    }

    // MARK: - coherenceTrend

    func testCoherenceTrendOldestFirst() {
        let base = Date()
        let sessions = makeSessions(10, base: base)
        let points = TrendEngine.coherenceTrend(sessions: sessions)
        XCTAssertEqual(points.count, 10)
        for i in 1..<points.count {
            XCTAssertLessThanOrEqual(points[i-1].date, points[i].date)
        }
    }

    func testCoherenceTrendFieldsMapped() {
        let base = Date()
        let s = session(daysAgo: 0, base: base, bpm: 5.5, coherence: 0.82)
        let points = TrendEngine.coherenceTrend(sessions: [s])
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].coherenceScore, 0.82, accuracy: 0.001)
        XCTAssertEqual(points[0].bpm, 5.5, accuracy: 0.001)
        XCTAssertEqual(points[0].sessionId, s.id)
    }

    func testCoherenceTrendEmpty() {
        XCTAssertEqual(TrendEngine.coherenceTrend(sessions: []).count, 0)
    }

    func testCoherenceTrend30Sessions() {
        let points = TrendEngine.coherenceTrend(sessions: makeSessions(30))
        XCTAssertEqual(points.count, 30)
    }

    func testCoherenceTrend90Sessions() {
        let points = TrendEngine.coherenceTrend(sessions: makeSessions(90))
        XCTAssertEqual(points.count, 90)
    }

    // MARK: - dailyHRVTrend

    func testDailyHRVGroups2SessionsOnSameDay() {
        let base = Date()
        let t = cal.startOfDay(for: base)
        let s1 = BreathingSessionRecord(
            id: "a", timestamp: t.addingTimeInterval(3600),
            durationSeconds: 300, bpm: 6, ratio: "4:6",
            baselineHRV: 50, recoveryHRV: 55, avgHRV: 60,
            coherenceScore: 0.7, reflectionRating: nil)
        let s2 = BreathingSessionRecord(
            id: "b", timestamp: t.addingTimeInterval(7200),
            durationSeconds: 300, bpm: 6, ratio: "4:6",
            baselineHRV: 50, recoveryHRV: 55, avgHRV: 80,
            coherenceScore: 0.7, reflectionRating: nil)
        let trend = TrendEngine.dailyHRVTrend(sessions: [s1, s2], calendar: cal)
        XCTAssertEqual(trend.count, 1)
        XCTAssertEqual(trend[0].averageHRV, 70.0, accuracy: 0.001)
        XCTAssertEqual(trend[0].sessionCount, 2)
    }

    func testDailyHRVExcludesZeroHRV() {
        let base = Date()
        let s = session(daysAgo: 0, base: base, hrv: 0)
        let trend = TrendEngine.dailyHRVTrend(sessions: [s], calendar: cal)
        XCTAssertEqual(trend.count, 0)
    }

    func testDailyHRVOldestFirst() {
        let base = Date()
        let sessions = makeSessions(10, base: base)
        let trend = TrendEngine.dailyHRVTrend(sessions: sessions, calendar: cal)
        XCTAssertEqual(trend.count, 10)
        for i in 1..<trend.count {
            XCTAssertLessThan(trend[i-1].date, trend[i].date)
        }
    }

    func testDailyHRV30Days() {
        let base = Date()
        let sessions = makeSessions(30, base: base)
        let trend = TrendEngine.dailyHRVTrend(sessions: sessions, calendar: cal)
        XCTAssertEqual(trend.count, 30)
    }

    func testDailyHRV90DaysMultiplePerDay() {
        let base = Date()
        // Two sessions per day for 45 days = 90 sessions, 45 daily points
        var sessions: [BreathingSessionRecord] = []
        for d in 0..<45 {
            let dayDate = day(-d, from: base)
            sessions.append(BreathingSessionRecord(
                id: UUID().uuidString,
                timestamp: dayDate.addingTimeInterval(3600),
                durationSeconds: 300, bpm: 6, ratio: "4:6",
                baselineHRV: 50, recoveryHRV: 55, avgHRV: 50,
                coherenceScore: 0.7, reflectionRating: nil))
            sessions.append(BreathingSessionRecord(
                id: UUID().uuidString,
                timestamp: dayDate.addingTimeInterval(7200),
                durationSeconds: 300, bpm: 6, ratio: "4:6",
                baselineHRV: 50, recoveryHRV: 55, avgHRV: 70,
                coherenceScore: 0.7, reflectionRating: nil))
        }
        let trend = TrendEngine.dailyHRVTrend(sessions: sessions, calendar: cal)
        XCTAssertEqual(trend.count, 45)
        for point in trend {
            XCTAssertEqual(point.averageHRV, 60.0, accuracy: 0.001)
            XCTAssertEqual(point.sessionCount, 2)
        }
    }

    // MARK: - consistencyStats

    func testConsistencyStatsTotals() {
        let base = Date()
        let sessions = makeSessions(10, base: base)
        let stats = TrendEngine.consistencyStats(sessions: sessions, today: base, calendar: cal)
        XCTAssertEqual(stats.totalSessions, 10)
    }

    func testConsistencyStatsLast7() {
        let base = Date()
        // 10 sessions: days 0-9 ago; last 7 = days 0-6
        let sessions = makeSessions(10, base: base)
        let stats = TrendEngine.consistencyStats(sessions: sessions, today: base, calendar: cal)
        XCTAssertEqual(stats.last7Days, 7)
    }

    func testConsistencyStatsLast30() {
        let base = Date()
        let sessions = makeSessions(30, base: base)
        let stats = TrendEngine.consistencyStats(sessions: sessions, today: base, calendar: cal)
        XCTAssertEqual(stats.last30Days, 30)
    }

    func testCurrentStreakContinuous() {
        let base = Date()
        // 10 consecutive days ending today → streak = 10
        let sessions = makeSessions(10, base: base)
        let stats = TrendEngine.consistencyStats(sessions: sessions, today: base, calendar: cal)
        XCTAssertEqual(stats.currentStreak, 10)
    }

    func testCurrentStreakBrokenYesterday() {
        let base = Date()
        // Session today and 2 days ago (skipped yesterday) → streak = 1
        let s1 = session(daysAgo: 0, base: base)
        let s2 = session(daysAgo: 2, base: base)
        let stats = TrendEngine.consistencyStats(sessions: [s1, s2], today: base, calendar: cal)
        XCTAssertEqual(stats.currentStreak, 1)
    }

    func testCurrentStreakZeroWhenNoSessionToday() {
        let base = Date()
        let s = session(daysAgo: 1, base: base)
        let stats = TrendEngine.consistencyStats(sessions: [s], today: base, calendar: cal)
        XCTAssertEqual(stats.currentStreak, 0)
    }

    func testLongestStreak() {
        let base = Date()
        // Days 0-4 (5 days), gap, days 10-13 (4 days)
        var sessions: [BreathingSessionRecord] = []
        for d in 0...4  { sessions.append(session(daysAgo: d, base: base)) }
        for d in 10...13 { sessions.append(session(daysAgo: d, base: base)) }
        let stats = TrendEngine.consistencyStats(sessions: sessions, today: base, calendar: cal)
        XCTAssertEqual(stats.longestStreak, 5)
    }

    func testConsistencyStats90Sessions() {
        let base = Date()
        let sessions = makeSessions(90, base: base)
        let stats = TrendEngine.consistencyStats(sessions: sessions, today: base, calendar: cal)
        XCTAssertEqual(stats.totalSessions, 90)
        XCTAssertEqual(stats.last30Days, 30)
        XCTAssertEqual(stats.currentStreak, 90)
        XCTAssertEqual(stats.longestStreak, 90)
    }

    func testConsistencyStatsEmpty() {
        let stats = TrendEngine.consistencyStats(sessions: [], today: Date(), calendar: cal)
        XCTAssertEqual(stats.totalSessions, 0)
        XCTAssertEqual(stats.currentStreak, 0)
        XCTAssertEqual(stats.longestStreak, 0)
    }

    // MARK: - summaryStats

    func testSummaryStatsEmpty() {
        let s = TrendEngine.summaryStats(sessions: [])
        XCTAssertEqual(s.sessionCount, 0)
        XCTAssertNil(s.mostUsedBPM)
    }

    func testSummaryStatsAverages() {
        let base = Date()
        let sessions = [
            session(daysAgo: 0, base: base, bpm: 6.0, coherence: 0.8, hrv: 60, duration: 300),
            session(daysAgo: 1, base: base, bpm: 6.0, coherence: 0.6, hrv: 40, duration: 600),
        ]
        let s = TrendEngine.summaryStats(sessions: sessions)
        XCTAssertEqual(s.sessionCount, 2)
        XCTAssertEqual(s.avgCoherence, 0.7, accuracy: 0.001)
        XCTAssertEqual(s.avgHRV, 50.0, accuracy: 0.001)
        XCTAssertEqual(s.avgDurationMinutes, 7.5, accuracy: 0.001)
    }

    func testSummaryStatsMostUsedBPM() {
        let base = Date()
        let sessions = [
            session(daysAgo: 0, base: base, bpm: 5.5),
            session(daysAgo: 1, base: base, bpm: 6.0),
            session(daysAgo: 2, base: base, bpm: 6.0),
        ]
        let s = TrendEngine.summaryStats(sessions: sessions)
        XCTAssertEqual(s.mostUsedBPM, 6.0)
    }
}
