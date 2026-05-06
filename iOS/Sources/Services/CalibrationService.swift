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
        case failed(message: String, diagnostics: String?)
    }

    @Published public private(set) var calibrationState: CalibrationState = .idle

    private let candidates = CalibrationEngine.candidateBPMs
    private let defaultPerRateDuration: TimeInterval = 60

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
    public func startCalibration(sampleDurationPerRate: TimeInterval? = nil) -> Bool {
        guard watchService?.sendStartCalibration(
            sampleDurationPerRate: sampleDurationPerRate) == true else { return false }
        startLocalProgressTimer(perRateDuration: sampleDurationPerRate ?? defaultPerRateDuration)
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
    public func failFromWatch(_ payload: CalibrationFailurePayload? = nil) {
        stopProgressTimer()
        calibrationState = .failed(
            message: failureMessage(from: payload),
            diagnostics: failureDiagnostics(from: payload))
    }

    // MARK: - Local progress timer

    private func startLocalProgressTimer(perRateDuration: TimeInterval) {
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
                let rateIndex = min(Int(elapsed / perRateDuration), self.candidates.count - 1)
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

    private func failureMessage(from payload: CalibrationFailurePayload?) -> String {
        guard let payload else {
            return "Not enough HRV data was collected. Make sure your Apple Watch is snug and try again."
        }
        switch payload.reason {
        case .insufficientSamples:
            return "Insufficient HRV readings were captured. Wear your Apple Watch snugly, keep your wrist still, and try again."
        case .noResonanceSignal:
            return "Your readings were captured, but no clear resonance signal was detected. Try again in a quieter resting position."
        }
    }

    private func failureDiagnostics(from payload: CalibrationFailurePayload?) -> String? {
        guard let payload else { return nil }
        let perRate = CalibrationEngine.candidateBPMs
            .map { bpm in
                "\(String(format: "%.1f", bpm)):\(payload.perRateSampleCounts[bpm] ?? 0)"
            }
            .joined(separator: "  ")
        let heartRate = payload.latestHeartRate > 0
            ? String(format: "%.0f bpm", payload.latestHeartRate)
            : "none"
        return """
        Reason: \(payload.reason.rawValue)
        HK active: \(payload.workoutWasActive ? "yes" : "no")
        HK samples: \(payload.hkSampleCount)
        Accepted rates: \(payload.acceptedRateCount)/\(payload.totalRateCount)
        Latest HR: \(heartRate)
        Per-rate: \(perRate)
        """
    }
}
