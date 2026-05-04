import Foundation
import AmachBreatheShared

/// Orchestrates calibration from the iPhone side.
/// Sends a single `.startCalibration` command to the Watch, then drives a local
/// progress timer that mirrors the Watch's 6×60s protocol. When the Watch finishes
/// it sends back a `ResonanceFrequencyResult`; `AmachBreatheApp` calls
/// `completeWithResult(_:)` to surface it here.
@MainActor
public final class CalibrationService: ObservableObject {

    public enum CalibrationState {
        case idle
        case running(currentBPM: Double, elapsed: TimeInterval, total: TimeInterval)
        /// Local timer expired but Watch hasn't sent the result back yet.
        /// Watch finalize includes per-rate analysis after the last tone, so
        /// the iPhone may sit here for a couple of seconds.
        case awaitingResult
        case complete(result: ResonanceFrequencyResult)
        case failed
    }

    @Published public private(set) var calibrationState: CalibrationState = .idle

    private let candidates = CalibrationEngine.candidateBPMs
    private let perRateDuration: TimeInterval = 60

    private var watchService: WatchConnectivityService?
    private var progressTimer: Timer?

    public init(watchService: WatchConnectivityService? = nil,
                store: CalibrationStore? = nil) {
        self.watchService = watchService
    }

    // MARK: - Public API

    /// Sends `.startCalibration` to Watch and starts the local progress display.
    /// Returns `false` when Watch is not reachable — caller should prompt the user.
    @discardableResult
    public func startCalibration() -> Bool {
        guard watchService?.sendStartCalibration() == true else { return false }
        startLocalProgressTimer()
        return true
    }

    public func cancel() {
        stopProgressTimer()
        calibrationState = .idle
        watchService?.sendCancelSession()
    }

    /// Called by `AmachBreatheApp` when the Watch sends back a `ResonanceFrequencyResult`.
    public func completeWithResult(_ result: ResonanceFrequencyResult) {
        stopProgressTimer()
        calibrationState = .complete(result: result)
    }

    /// Called when the Watch reports calibration finished without enough HRV
    /// data to identify a resonance frequency.
    public func failFromWatch() {
        stopProgressTimer()
        calibrationState = .failed
    }

    // MARK: - Local progress timer

    private func startLocalProgressTimer() {
        stopProgressTimer()
        let total = Double(candidates.count) * perRateDuration
        let startTime = Date()
        calibrationState = .running(currentBPM: candidates[0], elapsed: 0, total: total)

        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed >= total {
                    self.stopProgressTimer()
                    // Don't leave the UI frozen on "1 min left" — the Watch
                    // still has to evaluate per-rate scores and ship the
                    // result over WC. Show an explicit waiting state until
                    // completeWithResult is called.
                    if case .complete = self.calibrationState { return }
                    self.calibrationState = .awaitingResult
                    return
                }
                let rateIndex = min(Int(elapsed / self.perRateDuration), self.candidates.count - 1)
                self.calibrationState = .running(
                    currentBPM: self.candidates[rateIndex],
                    elapsed: elapsed,
                    total: total)
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}
