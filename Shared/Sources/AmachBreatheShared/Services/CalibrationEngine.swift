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
    /// Uses raw Goertzel amplitude (proportional to oscillation amplitude in ms)
    /// so that larger breathing-driven oscillations compare correctly across rates.
    /// Rates with insufficient data are skipped.
    public func findResonance(
        samples: [Double: [Double]]
    ) -> ResonanceFrequencyResult? {
        var scores: [Double: Double] = [:]
        for bpm in Self.candidateBPMs {
            guard let rr = samples[bpm],
                  rr.count >= Self.minSamplesPerRate else { continue }
            if let amp = coherenceCalc.rawAmplitude(rrIntervals: rr, targetBPM: bpm) {
                scores[bpm] = amp
            }
        }
        // Tiebreaker: when two rates share the same amplitude, prefer the lower BPM.
        // Lower BPM is more conservative (slower breath rate → gentler physiological demand).
        guard let best = scores.max(by: { a, b in
            if a.value != b.value { return a.value < b.value }
            return a.key > b.key   // equal amplitude → higher BPM is "less" → lower BPM wins
        }) else { return nil }
        // Normalise scores to 0–1 relative to max amplitude for consistent storage.
        let maxAmp = best.value
        let normScores = scores.mapValues { maxAmp > 0 ? $0 / maxAmp : 0 }
        return ResonanceFrequencyResult(resonanceBPM: best.key, scores: normScores)
    }

    /// Convenience: evaluate a single RR array against all candidates.
    /// Useful only for testing; real calibration passes per-rate data.
    public func findResonanceFromSingleWindow(
        rrIntervals: [Double]
    ) -> ResonanceFrequencyResult? {
        let samples = Dictionary(uniqueKeysWithValues: Self.candidateBPMs.map { ($0, rrIntervals) })
        return findResonance(samples: samples)
    }

    // MARK: - Per-rate amplitude

    /// Raw Goertzel amplitude at `bpm` Hz — proportional to RR oscillation amplitude.
    public func amplitude(rrIntervals: [Double], bpm: Double) -> Double? {
        guard rrIntervals.count >= Self.minSamplesPerRate else { return nil }
        return coherenceCalc.rawAmplitude(rrIntervals: rrIntervals, targetBPM: bpm)
    }
}
