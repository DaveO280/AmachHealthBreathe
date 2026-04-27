import Foundation

/// Computes RMSSD from a rolling 30-second window of RR intervals (in milliseconds).
public final class HRVProcessor: @unchecked Sendable {

    private let windowDuration: TimeInterval
    private var samples: [(timestamp: Date, rr: Double)] = []  // rr in ms
    private let lock = NSLock()

    public init(windowDuration: TimeInterval = 30) {
        self.windowDuration = windowDuration
    }

    /// Add a new RR interval sample (milliseconds).
    public func addRRInterval(_ rr: Double, at timestamp: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        samples.append((timestamp, rr))
        pruneWindow(relativeTo: timestamp)
    }

    /// Current RMSSD over the rolling window, or nil if fewer than 2 samples.
    public var rmssd: Double? {
        lock.lock()
        defer { lock.unlock() }
        return computeRMSSD(samples.map(\.rr))
    }

    /// All RR intervals currently in the window (milliseconds).
    public var currentWindow: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return samples.map(\.rr)
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll()
    }

    // MARK: - Private

    private func pruneWindow(relativeTo now: Date) {
        let cutoff = now.addingTimeInterval(-windowDuration)
        samples.removeAll { $0.timestamp < cutoff }
    }

    private func computeRMSSD(_ rr: [Double]) -> Double? {
        guard rr.count >= 2 else { return nil }
        var sumSq = 0.0
        for i in 1 ..< rr.count {
            let diff = rr[i] - rr[i - 1]
            sumSq += diff * diff
        }
        return sqrt(sumSq / Double(rr.count - 1))
    }
}
