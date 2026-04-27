import Foundation

/// Stored result of a resonance frequency calibration run.
/// One record per user; retestAfter signals when to redo the calibration.
public struct CalibrationRecord: Codable, Sendable {
    public let resonanceBPM: Double
    /// BPM → coherence/amplitude score (0…1) for each candidate rate
    public let scores: [Double: Double]
    public let createdAt: Date
    /// Recommended retest window — 30 days from creation.
    public let retestAfter: Date

    public init(resonanceBPM: Double, scores: [Double: Double], createdAt: Date = Date()) {
        self.resonanceBPM = resonanceBPM
        self.scores = scores
        self.createdAt = createdAt
        self.retestAfter = createdAt.addingTimeInterval(30 * 24 * 3600)
    }

    public init(result: ResonanceFrequencyResult, createdAt: Date = Date()) {
        self.init(resonanceBPM: result.resonanceBPM, scores: result.scores, createdAt: createdAt)
    }

    public var needsRetest: Bool { Date() >= retestAfter }
}
