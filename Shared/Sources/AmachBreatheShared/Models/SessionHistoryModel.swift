import Foundation

/// Pure data model for the history list. Transforms BreathingSessionRecord
/// into display-ready rows sorted newest-first.
public struct SessionHistoryModel: Sendable {

    public struct Row: Identifiable, Sendable {
        public let id: String
        public let timestamp: Date
        public let durationMinutes: Int
        public let bpm: Double
        public let ratio: String
        public let avgHRV: Double        // ms
        public let coherenceScore: Double // 0–1
        public let reflectionRating: Int? // 1–5

        /// Short date string, e.g. "Apr 27"
        public var dateLabel: String {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: timestamp)
        }

        /// "5 min" / "10 min" / "15 min"
        public var durationLabel: String { "\(durationMinutes) min" }

        public var coherencePercent: Int { Int((coherenceScore * 100).rounded()) }
    }

    /// Sorted newest-first. Sessions with duration 0 are filtered out.
    public static func rows(
        from sessions: [BreathingSessionRecord]
    ) -> [Row] {
        sessions
            .filter { $0.durationSeconds > 0 }
            .sorted { $0.timestamp > $1.timestamp }
            .map { row(from: $0) }
    }

    public static func row(from record: BreathingSessionRecord) -> Row {
        Row(
            id: record.id,
            timestamp: record.timestamp,
            durationMinutes: max(1, record.durationSeconds / 60),
            bpm: record.bpm,
            ratio: record.ratio,
            avgHRV: record.avgHRV,
            coherenceScore: record.coherenceScore,
            reflectionRating: record.reflectionRating
        )
    }
}
