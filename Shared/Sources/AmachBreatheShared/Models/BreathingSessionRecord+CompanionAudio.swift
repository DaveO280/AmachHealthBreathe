import Foundation

extension BreathingSessionRecord {

    /// Attaches phone-captured audio metrics to a watch session when the record has none yet.
    /// Idempotent: returns `self` when metrics are already present or `companionMetrics` is nil.
    public func mergingCompanionAudioMetrics(_ companionMetrics: AudioBreathMetrics?) -> BreathingSessionRecord {
        guard audioBreathMetrics == nil, let companionMetrics else { return self }
        return BreathingSessionRecord(
            id: id,
            timestamp: timestamp,
            durationSeconds: durationSeconds,
            bpm: bpm,
            ratio: ratio,
            baselineHRV: baselineHRV,
            recoveryHRV: recoveryHRV,
            avgHRV: avgHRV,
            coherenceScore: coherenceScore,
            reflectionRating: reflectionRating,
            source: source,
            audioBreathMetrics: companionMetrics
        )
    }
}
