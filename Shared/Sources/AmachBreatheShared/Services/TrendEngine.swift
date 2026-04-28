import Foundation

/// Computes trend data from a collection of BreathingSessionRecords.
/// All methods are pure functions — no I/O, safe to call from tests.
public enum TrendEngine {

    // MARK: - Coherence trend

    public struct CoherencePoint: Sendable {
        public let date: Date
        public let sessionId: String
        public let coherenceScore: Double
        public let bpm: Double
        public init(date: Date, sessionId: String,
                    coherenceScore: Double, bpm: Double) {
            self.date = date; self.sessionId = sessionId
            self.coherenceScore = coherenceScore; self.bpm = bpm
        }
    }

    /// Returns one point per session, oldest-first.
    public static func coherenceTrend(
        sessions: [BreathingSessionRecord]
    ) -> [CoherencePoint] {
        sessions
            .sorted { $0.timestamp < $1.timestamp }
            .map { CoherencePoint(date: $0.timestamp, sessionId: $0.id,
                                  coherenceScore: $0.coherenceScore ?? 0, bpm: $0.bpm) }
    }

    // MARK: - HRV trend (from session avgHRV, one point per day)

    public struct DailyHRV: Sendable {
        public let date: Date            // midnight of the day (calendar day)
        public let averageHRV: Double    // mean of all session avgHRV on this day
        public let sessionCount: Int
        public init(date: Date, averageHRV: Double, sessionCount: Int) {
            self.date = date; self.averageHRV = averageHRV
            self.sessionCount = sessionCount
        }
    }

    /// Groups sessions by calendar day, oldest-first. Zero-HRV sessions excluded.
    public static func dailyHRVTrend(
        sessions: [BreathingSessionRecord],
        calendar: Calendar = .current
    ) -> [DailyHRV] {
        let valid = sessions.filter { ($0.avgHRV ?? 0) > 0 }
        let grouped = Dictionary(grouping: valid) { s in
            calendar.startOfDay(for: s.timestamp)
        }
        return grouped
            .map { day, records in
                let avg = records.map { $0.avgHRV ?? 0 }.reduce(0, +) / Double(records.count)
                return DailyHRV(date: day, averageHRV: avg, sessionCount: records.count)
            }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Practice consistency

    public struct ConsistencyStats: Sendable {
        public let totalSessions: Int
        public let last7Days: Int
        public let last30Days: Int
        public let currentStreak: Int   // consecutive calendar days ending on `today` with ≥1 session
        public let longestStreak: Int
        public init(totalSessions: Int, last7Days: Int, last30Days: Int,
                    currentStreak: Int, longestStreak: Int) {
            self.totalSessions = totalSessions; self.last7Days = last7Days
            self.last30Days = last30Days; self.currentStreak = currentStreak
            self.longestStreak = longestStreak
        }
    }

    public static func consistencyStats(
        sessions: [BreathingSessionRecord],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> ConsistencyStats {
        let total = sessions.count
        let todayStart = calendar.startOfDay(for: today)

        let last7Start  = calendar.date(byAdding: .day, value: -6,  to: todayStart)!
        let last30Start = calendar.date(byAdding: .day, value: -29, to: todayStart)!

        let last7  = sessions.filter { $0.timestamp >= last7Start }.count
        let last30 = sessions.filter { $0.timestamp >= last30Start }.count

        // Collect set of active days
        let activeDays = Set(sessions.map {
            calendar.startOfDay(for: $0.timestamp)
        })

        // Current streak: walk backwards from today
        var current = 0
        var day = todayStart
        while activeDays.contains(day) {
            current += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }

        // Longest streak: scan sorted active days
        let sortedDays = activeDays.sorted()
        var longest = sortedDays.isEmpty ? 0 : 1
        var run = sortedDays.isEmpty ? 0 : 1
        for i in stride(from: 1, to: sortedDays.count, by: 1) {
            let diff = calendar.dateComponents(
                [.day], from: sortedDays[i-1], to: sortedDays[i]).day ?? 0
            if diff == 1 { run += 1; longest = max(longest, run) }
            else { run = 1 }
        }

        return ConsistencyStats(
            totalSessions: total, last7Days: last7, last30Days: last30,
            currentStreak: current, longestStreak: longest
        )
    }

    // MARK: - Summary stats for a window of sessions

    public struct SummaryStats: Sendable {
        public let sessionCount: Int
        public let avgCoherence: Double
        public let avgHRV: Double
        public let avgDurationMinutes: Double
        public let mostUsedBPM: Double?
    }

    public static func summaryStats(
        sessions: [BreathingSessionRecord]
    ) -> SummaryStats {
        guard !sessions.isEmpty else {
            return SummaryStats(sessionCount: 0, avgCoherence: 0,
                                avgHRV: 0, avgDurationMinutes: 0, mostUsedBPM: nil)
        }
        let n = Double(sessions.count)
        let avgCoherence = sessions.map { $0.coherenceScore ?? 0 }.reduce(0, +) / n
        let avgHRV = sessions.map { $0.avgHRV ?? 0 }.reduce(0, +) / n
        let avgDur = sessions.map { Double($0.durationSeconds) / 60 }.reduce(0, +) / n

        // Mode BPM
        let bpmCounts = Dictionary(grouping: sessions, by: \.bpm)
            .mapValues(\.count)
        let mostUsed = bpmCounts.max(by: { $0.value < $1.value })?.key

        return SummaryStats(
            sessionCount: sessions.count, avgCoherence: avgCoherence,
            avgHRV: avgHRV, avgDurationMinutes: avgDur, mostUsedBPM: mostUsed
        )
    }
}
