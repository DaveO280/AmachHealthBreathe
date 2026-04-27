import Foundation
import AmachBreatheShared

/// Persists a single CalibrationRecord per user in UserDefaults.
/// Exposes a needsRetest flag to prompt re-calibration after 30 days.
@MainActor
public final class CalibrationStore: ObservableObject {

    @Published public private(set) var record: CalibrationRecord?

    public var needsRetest: Bool {
        record?.needsRetest ?? true
    }

    public var resonanceBPM: Double {
        record?.resonanceBPM ?? 5.5   // sensible default
    }

    private let storageKey = "com.amach.breathe.calibration"

    public init() { load() }

    // MARK: - Persistence

    public func save(_ record: CalibrationRecord) {
        self.record = record
        persist()
    }

    public func save(result: ResonanceFrequencyResult) {
        save(CalibrationRecord(result: result))
    }

    public func clear() {
        record = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Private

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(
                  CalibrationRecord.self, from: data) else { return }
        record = decoded
    }

    private func persist() {
        guard let record,
              let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
