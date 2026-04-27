import Foundation
import AmachBreatheShared

/// Runs a resonance frequency calibration: tests each candidate BPM rate
/// for 60–90 seconds, then picks the rate with highest coherence score.
/// This is an iPhone-side orchestrator; the Watch does the actual HRV measurement.
@MainActor
public final class CalibrationService: ObservableObject {

    public enum CalibrationState {
        case idle
        case running(currentBPM: Double, elapsed: TimeInterval, total: TimeInterval)
        case complete(result: ResonanceFrequencyResult)
        case failed
    }

    @Published public private(set) var calibrationState: CalibrationState = .idle

    private let candidates: [Double] = [4.5, 5.0, 5.5, 6.0, 6.5, 7.0]
    private let perRateDuration: TimeInterval = 60   // seconds per candidate

    private var watchService: WatchConnectivityService?
    private var collectedScores: [Double: Double] = [:]
    private var candidateIndex: Int = 0
    private var phaseTimer: Timer?

    public init(watchService: WatchConnectivityService? = nil) {
        self.watchService = watchService
    }

    public func startCalibration() {
        collectedScores = [:]
        candidateIndex = 0
        advanceToNextCandidate()
    }

    public func cancel() {
        phaseTimer?.invalidate()
        phaseTimer = nil
        calibrationState = .idle
        watchService?.sendCancelSession()
    }

    /// Called by WatchConnectivityService when a session result arrives during calibration.
    public func recordCalibrationScore(bpm: Double, coherenceScore: Double) {
        collectedScores[bpm] = coherenceScore
        advanceToNextCandidate()
    }

    // MARK: - Private

    private func advanceToNextCandidate() {
        guard candidateIndex < candidates.count else {
            finalize()
            return
        }

        let bpm = candidates[candidateIndex]
        candidateIndex += 1

        let total = Double(candidates.count) * perRateDuration
        let elapsed = Double(candidateIndex - 1) * perRateDuration

        calibrationState = .running(currentBPM: bpm, elapsed: elapsed, total: total)
        watchService?.sendStartSession(bpm: bpm, durationSeconds: Int(perRateDuration))
    }

    private func finalize() {
        guard let best = collectedScores.max(by: { $0.value < $1.value }) else {
            calibrationState = .failed
            return
        }
        let result = ResonanceFrequencyResult(resonanceBPM: best.key, scores: collectedScores)
        calibrationState = .complete(result: result)
    }
}
