import Foundation

/// Measures cardiac coherence: spectral power at the target breathing frequency
/// relative to total HRV power, using the Goertzel algorithm.
///
/// Coherence score = power(targetFreq) / totalPower, clamped to 0–1.
/// A score ≥ 0.65 indicates high coherence (Heart Math threshold).
public final class CoherenceCalculator: @unchecked Sendable {

    private let lock = NSLock()

    /// Sample rate of the RR interval series (Hz). Typical HRV analysis uses ~4 Hz.
    private let sampleRate: Double

    public init(sampleRate: Double = 4.0) {
        self.sampleRate = sampleRate
    }

    // MARK: - Public

    /// Compute coherence score for a given target breathing rate.
    /// - Parameters:
    ///   - rrIntervals: RR intervals in milliseconds (chronological order)
    ///   - targetBPM: breathing rate in breaths per minute (e.g. 5.5)
    /// - Returns: coherence score 0…1, or nil if insufficient data
    public func coherenceScore(rrIntervals: [Double], targetBPM: Double) -> Double? {
        guard rrIntervals.count >= 8 else { return nil }

        // Interpolate RR intervals to evenly-spaced time series at sampleRate
        let evenlySampled = interpolate(rrIntervals: rrIntervals)
        guard evenlySampled.count >= 8 else { return nil }

        let targetFreq = targetBPM / 60.0   // BPM → Hz

        let targetPower = goertzel(signal: evenlySampled, frequency: targetFreq, sampleRate: sampleRate)

        // Total power = sum of Goertzel power across the HRV band (0.04–0.4 Hz).
        // Using spectral sum keeps the denominator in the same units as the numerator.
        let total = hrvBandPower(evenlySampled)
        guard total > 0 else { return nil }

        return min(targetPower / total, 1.0)
    }

    /// Evaluate coherence at all candidate BPM rates and return the best one.
    public func resonanceBPM(
        rrIntervals: [Double],
        candidates: [Double] = [4.5, 5.0, 5.5, 6.0, 6.5, 7.0]
    ) -> ResonanceFrequencyResult? {
        guard rrIntervals.count >= 8 else { return nil }

        var scores: [Double: Double] = [:]
        for bpm in candidates {
            if let score = coherenceScore(rrIntervals: rrIntervals, targetBPM: bpm) {
                scores[bpm] = score
            }
        }
        guard let best = scores.max(by: { $0.value < $1.value }) else { return nil }
        return ResonanceFrequencyResult(resonanceBPM: best.key, scores: scores)
    }

    // MARK: - Raw amplitude

    /// Un-normalized Goertzel amplitude (sqrt of spectral power) at `targetBPM`.
    /// Proportional to the actual RR oscillation amplitude in milliseconds.
    /// Use this for comparing across different breathing rates (calibration).
    /// Use `coherenceScore` for the live 0–1 display metric during sessions.
    public func rawAmplitude(rrIntervals: [Double], targetBPM: Double) -> Double? {
        guard rrIntervals.count >= 8 else { return nil }
        let evenlySampled = interpolate(rrIntervals: rrIntervals)
        guard evenlySampled.count >= 8 else { return nil }
        let power = goertzel(signal: evenlySampled, frequency: targetBPM / 60.0,
                             sampleRate: sampleRate)
        return sqrt(max(0, power))
    }

    // MARK: - Private

    /// Goertzel algorithm: efficient single-frequency DFT bin computation.
    /// Returns the power (magnitude²) at `frequency` Hz.
    private func goertzel(signal: [Double], frequency: Double, sampleRate: Double) -> Double {
        let n = signal.count
        let k = Int((Double(n) * frequency / sampleRate).rounded())
        let omega = 2.0 * Double.pi * Double(k) / Double(n)
        let coeff = 2.0 * cos(omega)

        var s0 = 0.0, s1 = 0.0, s2 = 0.0
        for x in signal {
            s0 = x + coeff * s1 - s2
            s2 = s1
            s1 = s0
        }
        // Power = s1² + s2² - coeff·s1·s2
        return s1 * s1 + s2 * s2 - coeff * s1 * s2
    }

    /// Cumulative sum interpolation of RR intervals to 4 Hz evenly-spaced series.
    private func interpolate(rrIntervals: [Double]) -> [Double] {
        // Build cumulative time axis (seconds)
        var times: [Double] = [0]
        for rr in rrIntervals {
            times.append(times.last! + rr / 1000.0)
        }
        let totalDuration = times.last!
        let step = 1.0 / sampleRate
        var result: [Double] = []
        var t = 0.0
        var idx = 0
        while t <= totalDuration {
            // Find segment containing t
            while idx < times.count - 2 && times[idx + 1] < t { idx += 1 }
            let t0 = times[idx], t1 = times[idx + 1]
            let rr0 = rrIntervals[min(idx, rrIntervals.count - 1)]
            let rr1 = rrIntervals[min(idx + 1, rrIntervals.count - 1)]
            let frac = t1 > t0 ? (t - t0) / (t1 - t0) : 0.0
            result.append(rr0 + frac * (rr1 - rr0))
            t += step
        }
        return result
    }

    /// Sum of Goertzel power across the HRV band (0.04–0.40 Hz), step = frequency resolution.
    /// Using spectral sum keeps units consistent with single-bin Goertzel output.
    private func hrvBandPower(_ signal: [Double]) -> Double {
        let n = signal.count
        let freqResolution = sampleRate / Double(n)
        var total = 0.0
        var freq = 0.04
        while freq <= 0.40 {
            total += goertzel(signal: signal, frequency: freq, sampleRate: sampleRate)
            freq += freqResolution
        }
        return total
    }
}
