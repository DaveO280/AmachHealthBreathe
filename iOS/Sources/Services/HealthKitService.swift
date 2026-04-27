import Foundation
import HealthKit
import AmachBreatheShared

/// iPhone-only HealthKit fallback. When no Watch is available, reads step data
/// and logs breathing sessions to the Health store. Does NOT stream live HRV.
public final class HealthKitService: @unchecked Sendable {

    private let store = HKHealthStore()

    public init() { }

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate)
        ]
        let read: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN)
        ]
        try await store.requestAuthorization(toShare: share, read: read)
    }

    /// Save a completed breathing session as a Mindfulness workout in Health.
    public func saveBreathingWorkout(record: BreathingSessionRecord) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: record.timestamp)

        let end = record.timestamp.addingTimeInterval(Double(record.durationSeconds))
        try await builder.endCollection(at: end)
        _ = try? await builder.finishWorkout()
    }

    public func recentHeartRateSamples(limit: Int = 10) async -> [Double] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }

        let type = HKQuantityType(.heartRate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let bpms = (samples as? [HKQuantitySample])?.map {
                    $0.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
                } ?? []
                continuation.resume(returning: bpms)
            }
            self.store.execute(query)
        }
    }
}
