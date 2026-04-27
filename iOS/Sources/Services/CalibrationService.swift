import Foundation
import AmachBreatheShared

/// Orchestrates the 6-rate calibration protocol from the iPhone side.
/// Sends each rate to the Watch via WatchConnectivityService; waits for
/// session results (coherence score per rate); finalises via CalibrationEngine.
@MainActor
public final class CalibrationService: ObservableObject {

    public enum CalibrationState {
        case idle
        case running(currentBPM: Double, elapsed: TimeInterval, total: TimeInterval)
        case complete(result: ResonanceFrequencyResult)
        case failed
    }

    @Published public private(set) var calibrationState: CalibrationState = .idle

    private let candidates = CalibrationEngine.candidateBPMs
    private let perRateDuration: TimeInterval = 60
    private let engine = CalibrationEngine()

    private var watchService: WatchConnectivityService?
    private var store: CalibrationStore?
    private var collectedSamples: [Double: [Double]] = [:]  // bpm → RR window
    private var candidateIndex: Int = 0

    public init(watchService: WatchConnectivityService? = nil,
                store: CalibrationStore? = nil) {
        self.watchService = watchService
        self.store = store
    }

    // MARK: - Public API

    public func startCalibration() {
        collectedSamples = [:]
        candidateIndex = 0
        advanceToNextCandidate()
    }

    public func cancel() {
        calibrationState = .idle
        watchService?.sendCancelSession()
    }

    /// Called by WatchConnectivityService when a Watch session completes during calibration.
    /// `rrIntervals` is the RR window collected at `bpm`.
    public func recordRRWindow(bpm: Double, rrIntervals: [Double]) {
        collectedSamples[bpm] = rrIntervals
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

        watchService?.sendStartSession(bpm: bpm,
                                       durationSeconds: Int(perRateDuration))
    }

    private func finalize() {
        guard let result = engine.findResonance(samples: collectedSamples) else {
            calibrationState = .failed
            return
        }
        calibrationState = .complete(result: result)
        store?.save(result: result)
    }
}
