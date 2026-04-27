import HealthKit
import Combine
import AmachBreatheShared

/// Manages a HKWorkoutSession to keep the Watch screen awake and streams
/// live heart rate data, converting beat-to-beat intervals to RR intervals (ms).
@MainActor
public final class HKWorkoutSessionManager: NSObject, ObservableObject {

    // MARK: - Public

    /// Called on MainActor whenever a new RR interval arrives (milliseconds).
    public var onRRInterval: ((Double) -> Void)?

    @Published public private(set) var isActive: Bool = false
    @Published public private(set) var latestHeartRate: Double = 0   // BPM

    // MARK: - Private

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var liveBuilder: HKLiveWorkoutBuilder?

    // MARK: - Lifecycle

    public override init() { super.init() }

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let typesToShare: Set<HKSampleType> = [
            HKQuantityType(.heartRate),
            HKObjectType.workoutType()
        ]
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKObjectType.workoutType()
        ]
        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
    }

    public func startWorkout() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

        session.delegate = self
        builder.delegate = self

        workoutSession = session
        liveBuilder = builder

        session.startActivity(with: Date())
        try await builder.beginCollection(at: Date())

        isActive = true
    }

    public func stopWorkout() async {
        guard let session = workoutSession, let builder = liveBuilder else { return }
        session.end()
        do {
            try await builder.endCollection(at: Date())
            _ = try? await builder.finishWorkout()
        } catch { }
        workoutSession = nil
        liveBuilder = nil
        isActive = false
    }
}

// MARK: - HKWorkoutSessionDelegate

extension HKWorkoutSessionManager: HKWorkoutSessionDelegate {
    nonisolated public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) { }

    nonisolated public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) { }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension HKWorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }

    nonisolated public func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let hrType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hrType) else { return }

        let stats = workoutBuilder.statistics(for: hrType)
        let bpm = stats?.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute())) ?? 0

        guard bpm > 0 else { return }

        // Convert instantaneous HR to RR interval (ms)
        let rrMs = 60_000.0 / bpm

        Task { @MainActor [weak self] in
            self?.latestHeartRate = bpm
            self?.onRRInterval?(rrMs)
        }
    }
}
