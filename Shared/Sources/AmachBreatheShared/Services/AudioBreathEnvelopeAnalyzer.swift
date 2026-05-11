import Foundation

/// Pure envelope analyzer for optional microphone-based breath tracking.
/// It consumes already-derived amplitude samples; no raw audio reaches this type.
public final class AudioBreathEnvelopeAnalyzer: @unchecked Sendable {

    public struct Sample: Sendable {
        public let elapsed: TimeInterval
        public let amplitude: Double

        public init(elapsed: TimeInterval, amplitude: Double) {
            self.elapsed = elapsed
            self.amplitude = amplitude
        }
    }

    private let targetBPM: Double
    private let lock = NSLock()
    private var samples: [Sample] = []
    private var lastAcceptedElapsed: TimeInterval?

    public init(targetBPM: Double) {
        self.targetBPM = targetBPM
    }

    public func addAmplitude(_ amplitude: Double, elapsed: TimeInterval) {
        guard elapsed.isFinite, elapsed >= 0 else { return }
        let clamped = max(0, min(amplitude, 1))

        lock.lock()
        defer { lock.unlock() }

        // Downsample render callbacks to roughly 10 Hz. Breath timing is slow,
        // and this keeps storage/analysis stable without retaining audio.
        if let last = lastAcceptedElapsed, elapsed - last < 0.09 { return }
        lastAcceptedElapsed = elapsed

        let previous = samples.last?.amplitude ?? clamped
        let smoothed = (previous * 0.78) + (clamped * 0.22)
        samples.append(Sample(elapsed: elapsed, amplitude: smoothed))
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll()
        lastAcceptedElapsed = nil
    }

    public func metrics(permissionGranted: Bool = true) -> AudioBreathMetrics {
        lock.lock()
        let snapshot = samples
        lock.unlock()

        return Self.metrics(
            targetBPM: targetBPM,
            samples: snapshot,
            permissionGranted: permissionGranted
        )
    }

    public static func metrics(
        targetBPM: Double,
        samples: [Sample],
        permissionGranted: Bool = true
    ) -> AudioBreathMetrics {
        guard permissionGranted else {
            return AudioBreathMetrics(
                enabled: true,
                permissionGranted: false,
                targetBreathingBPM: targetBPM,
                dataQuality: .unavailable
            )
        }

        let duration = max(0, (samples.last?.elapsed ?? 0) - (samples.first?.elapsed ?? 0))
        guard samples.count >= 30, duration >= 20 else {
            return AudioBreathMetrics(
                enabled: true,
                permissionGranted: true,
                targetBreathingBPM: targetBPM,
                confidence: 0,
                dataQuality: .low,
                analyzedDurationSeconds: duration,
                sampleCount: samples.count
            )
        }

        let amplitudes = samples.map(\.amplitude).sorted()
        let floor = percentile(amplitudes, 0.20)
        let ceiling = percentile(amplitudes, 0.90)
        let dynamicRange = max(0, ceiling - floor)
        let signalToNoise = dynamicRange / max(0.001, floor)
        guard dynamicRange > 0.004 else {
            return AudioBreathMetrics(
                enabled: true,
                permissionGranted: true,
                targetBreathingBPM: targetBPM,
                confidence: 0.05,
                dataQuality: .low,
                analyzedDurationSeconds: duration,
                sampleCount: samples.count,
                signalToNoiseRatio: signalToNoise
            )
        }

        let threshold = floor + (dynamicRange * 0.42)
        let targetPeriod = 60.0 / max(targetBPM, 0.1)
        let minPeakSpacing = max(1.5, targetPeriod * 0.32)
        let peaks = detectedPeaks(
            samples: samples,
            threshold: threshold,
            minSpacing: minPeakSpacing
        )

        guard peaks.count >= 3 else {
            return AudioBreathMetrics(
                enabled: true,
                permissionGranted: true,
                targetBreathingBPM: targetBPM,
                confidence: 0.1,
                dataQuality: .low,
                analyzedDurationSeconds: duration,
                sampleCount: samples.count,
                detectedPeakCount: peaks.count,
                signalToNoiseRatio: signalToNoise
            )
        }

        let intervals = zip(peaks.dropFirst(), peaks).map { $0.elapsed - $1.elapsed }
            .filter { $0.isFinite && $0 > 0 }
            .sorted()
        guard let medianInterval = median(intervals) else {
            return AudioBreathMetrics(
                enabled: true,
                permissionGranted: true,
                targetBreathingBPM: targetBPM,
                confidence: 0.1,
                dataQuality: .low,
                analyzedDurationSeconds: duration,
                sampleCount: samples.count,
                detectedPeakCount: peaks.count,
                signalToNoiseRatio: signalToNoise
            )
        }

        // Breath sounds may produce one peak per full breath or one peak per
        // inhale/exhale half-cycle. Choose the interpretation closest to the
        // paced target, and lower confidence if it looks like half-cycle data.
        let fullCyclePeriod = medianInterval
        let halfCyclePeriod = medianInterval * 2
        let fullError = abs(fullCyclePeriod - targetPeriod) / targetPeriod
        let halfError = abs(halfCyclePeriod - targetPeriod) / targetPeriod
        let estimatedPeriod = halfError < fullError ? halfCyclePeriod : fullCyclePeriod
        let harmonicPenalty = halfError < fullError ? 0.82 : 1.0

        let estimatedBPM = 60.0 / max(estimatedPeriod, 0.1)
        let timingError = min(1, abs(estimatedPeriod - targetPeriod) / targetPeriod)
        let adherence = max(0, 1 - timingError)

        let variability = intervalVariability(intervals, medianInterval: medianInterval)
        let regularity = max(0, 1 - min(1, variability))
        let durationFactor = min(1, duration / 90.0)
        let peakCountFactor = min(1, Double(peaks.count) / 8.0)
        let snrFactor = min(1, signalToNoise / 4.0)
        let confidence = min(1, max(0, adherence * regularity * durationFactor * peakCountFactor * snrFactor * harmonicPenalty))
        let quality: AudioBreathDataQuality
        switch confidence {
        case 0.7...: quality = .good
        case 0.4..<0.7: quality = .fair
        default: quality = .low
        }

        return AudioBreathMetrics(
            enabled: true,
            permissionGranted: true,
            targetBreathingBPM: targetBPM,
            estimatedBreathingBPM: estimatedBPM,
            adherenceScore: adherence,
            confidence: confidence,
            dataQuality: quality,
            analyzedDurationSeconds: duration,
            sampleCount: samples.count,
            detectedPeakCount: peaks.count,
            signalToNoiseRatio: signalToNoise
        )
    }

    private static func detectedPeaks(
        samples: [Sample],
        threshold: Double,
        minSpacing: TimeInterval
    ) -> [Sample] {
        guard samples.count >= 3 else { return [] }
        var peaks: [Sample] = []

        for i in 1..<(samples.count - 1) {
            let prev = samples[i - 1]
            let current = samples[i]
            let next = samples[i + 1]
            guard current.amplitude > threshold,
                  current.amplitude >= prev.amplitude,
                  current.amplitude > next.amplitude else { continue }

            if let last = peaks.last, current.elapsed - last.elapsed < minSpacing {
                if current.amplitude > last.amplitude {
                    peaks[peaks.count - 1] = current
                }
            } else {
                peaks.append(current)
            }
        }
        return peaks
    }

    private static func percentile(_ sortedValues: [Double], _ p: Double) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        let clamped = max(0, min(p, 1))
        let index = Int((Double(sortedValues.count - 1) * clamped).rounded())
        return sortedValues[index]
    }

    private static func median(_ sortedValues: [Double]) -> Double? {
        guard !sortedValues.isEmpty else { return nil }
        let mid = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[mid - 1] + sortedValues[mid]) / 2
        }
        return sortedValues[mid]
    }

    private static func intervalVariability(
        _ sortedIntervals: [Double],
        medianInterval: Double
    ) -> Double {
        guard medianInterval > 0, !sortedIntervals.isEmpty else { return 1 }
        let deviations = sortedIntervals
            .map { abs($0 - medianInterval) / medianInterval }
            .sorted()
        return median(deviations) ?? 1
    }
}
