import Foundation

/// Identifies the resonance breathing rate by finding the BPM at which
/// HRV oscillation amplitude is highest across 6 candidate rates.
///
/// "HRV amplitude" = coherence score at target frequency (Goertzel, 0–1).
/// Using the normalized score keeps units consistent and is equivalent to
/// comparing raw spectral amplitudes across the same signal length.
public final class CalibrationEngine: Sendable {

    public static let candidateBPMs: [Double] = [4.5, 5.0, 5.5, 6.0, 6.5, 7.0]

    /// Minimum seconds of RR data required per candidate rate.
    public static let minSamplesPerRate = 8

    private let coherenceCalc = CoherenceCalculator()

    public init() {}

    // MARK: - API

    /// Given a map of bpm → RR interval array (ms), return resonance result.
    /// Rates with insufficient data are skipped.
    public func findResonance(
        samples: [Double: [Double]]
    ) -> ResonanceFrequencyResult? {
        var scores: [Double: Double] = [:]
        for bpm in Self.candidateBPMs {
            guard let rr = samples[bpm],
                  rr.count >= Self.minSamplesPerRate else { continue }
            if let score = coherenceCalc.coherenceScore(rrIntervals: rr, targetBPM: bpm) {
                scores[bpm] = score
            }
        }
        guard let best = scores.max(by: { $0.value < $1.value }) else { return nil }
        return ResonanceFrequencyResult(resonanceBPM: best.key, scores: scores)
    }

    /// Convenience: evaluate a single RR array against all candidates,
    /// treating the same data as representative for every rate.
    /// Useful only for testing; real calibration passes per-rate data.
    public func findResonanceFromSingleWindow(
        rrIntervals: [Double]
    ) -> ResonanceFrequencyResult? {
        let samples = Dictionary(uniqueKeysWithValues: Self.candidateBPMs.map { ($0, rrIntervals) })
        return findResonance(samples: samples)
    }

    // MARK: - Per-rate amplitude

    /// Coherence score (0–1) of `rrIntervals` at `bpm`. Returns nil if insufficient data.
    public func amplitude(rrIntervals: [Double], bpm: Double) -> Double? {
        guard rrIntervals.count >= Self.minSamplesPerRate else { return nil }
        return coherenceCalc.coherenceScore(rrIntervals: rrIntervals, targetBPM: bpm)
    }
}
