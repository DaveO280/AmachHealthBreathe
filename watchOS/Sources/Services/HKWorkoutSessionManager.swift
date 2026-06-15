import HealthKit
import Combine
import os
import AmachBreatheShared

/// Manages a HKWorkoutSession to keep the Watch screen awake and streams
/// live heart rate samples, converting each instantaneous BPM to a synthetic
/// RR interval (ms = 60_000/bpm). The HR oscillation across the breath cycle
/// (RSA) is what calibration / coherence Goertzel detects.
///
/// Two parallel sample sources, both feeding `onRRInterval`:
///   1. `HKLiveWorkoutBuilder` delegate — fires when the workout collects a
///      new heart-rate batch (typically every few seconds during a workout).
///   2. `HKAnchoredObjectQuery` on `.heartRate` — streams every new sample
///      written to the HealthKit store while the workout is active.
///
/// The anchored query exists because the workout-builder delegate has, on
/// real Watch SE hardware, occasionally not fired at all for `.mindAndBody`
/// configurations — leaving calibration with zero samples and no resonance.
/// Duplicates are harmless: HRVProcessor's window is time-pruned and the
/// repeated value just slightly over-weights one bin in the Goertzel.
@MainActor
public final class HKWorkoutSessionManager: NSObject, ObservableObject {

    // MARK: - Public

    /// Called on MainActor whenever a new RR interval arrives (milliseconds).
    public var onRRInterval: ((Double) -> Void)?

    @Published public private(set) var isActive: Bool = false
    @Published public private(set) var latestHeartRate: Double = 0   // BPM
    @Published public private(set) var sampleCount: Int = 0          // diagnostic
    private var loggedSampleMilestones: Set<Int> = []

    // MARK: - Private

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var liveBuilder: HKLiveWorkoutBuilder?
    private var hrAnchorQuery: HKAnchoredObjectQuery?

    nonisolated private static let log = Logger(
        subsystem: "com.amach.AmachBreathe", category: "HK")

    // MARK: - Lifecycle

    public override init() { super.init() }

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            DiagnosticLog.shared.record(
                source: "watchOS",
                category: "healthKit",
                level: .warning,
                message: "Health data unavailable")
            return
        }
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
        DiagnosticLog.shared.record(
            source: "watchOS",
            category: "healthKit",
            message: "HealthKit authorization requested")
    }

    public func startWorkout() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            DiagnosticLog.shared.record(
                source: "watchOS",
                category: "healthKit",
                level: .warning,
                message: "Workout not started; health data unavailable")
            return
        }

        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .indoor

        let session: HKWorkoutSession
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
        } catch {
            Self.log.error("HK_WORKOUT_INIT_FAILED \(error.localizedDescription, privacy: .public)")
            DiagnosticLog.shared.record(
                source: "watchOS",
                category: "healthKit",
                level: .error,
                message: "Workout init failed",
                metadata: ["error": error.localizedDescription])
            throw error
        }
        let builder = session.associatedWorkoutBuilder()
        let dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
        // Defaults for `.mindAndBody` are not contractual — be explicit so the
        // builder definitely collects heart rate. Without this, the
        // didCollectDataOf delegate may never fire on real hardware.
        dataSource.enableCollection(for: HKQuantityType(.heartRate), predicate: nil)
        builder.dataSource = dataSource

        session.delegate = self
        builder.delegate = self

        workoutSession = session
        liveBuilder = builder
        sampleCount = 0
        loggedSampleMilestones = []

        let startDate = Date()
        session.startActivity(with: startDate)
        do {
            try await builder.beginCollection(at: startDate)
        } catch {
            Self.log.error("HK_BEGIN_COLLECTION_FAILED \(error.localizedDescription, privacy: .public)")
            DiagnosticLog.shared.record(
                source: "watchOS",
                category: "healthKit",
                level: .error,
                message: "Workout begin collection failed",
                metadata: ["error": error.localizedDescription])
            throw error
        }

        // Belt-and-suspenders parallel HR stream — see class doc above.
        startHeartRateAnchorQuery(from: startDate)

        isActive = true
        Self.log.info("HK_WORKOUT_STARTED at \(startDate, privacy: .public)")
        DiagnosticLog.shared.record(
            source: "watchOS",
            category: "healthKit",
            message: "Workout started")
    }

    public func stopWorkout() async {
        if let q = hrAnchorQuery {
            healthStore.stop(q)
            hrAnchorQuery = nil
        }
        guard let session = workoutSession, let builder = liveBuilder else {
            isActive = false
            return
        }
        session.end()
        do {
            try await builder.endCollection(at: Date())
            _ = try? await builder.finishWorkout()
        } catch { }
        workoutSession = nil
        liveBuilder = nil
        isActive = false
        Self.log.info("HK_WORKOUT_STOPPED samples=\(self.sampleCount, privacy: .public)")
        DiagnosticLog.shared.record(
            source: "watchOS",
            category: "healthKit",
            message: "Workout stopped",
            metadata: ["samples": String(sampleCount)])
    }

    // MARK: - Anchored heart-rate stream

    private func startHeartRateAnchorQuery(from start: Date) {
        let hrType = HKQuantityType(.heartRate)
        // Only samples added AFTER the workout starts — past samples are
        // irrelevant and would pollute the HRVProcessor window.
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
        let query = HKAnchoredObjectQuery(
            type: hrType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.deliver(samples: samples)
        }
        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.deliver(samples: samples)
        }
        healthStore.execute(query)
        hrAnchorQuery = query
        Self.log.info("HK_ANCHOR_QUERY_STARTED")
        DiagnosticLog.shared.record(
            source: "watchOS",
            category: "healthKit",
            message: "Heart-rate anchor query started")
    }

    nonisolated private func deliver(samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else { return }
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let rrPairs: [(Double, Double)] = quantitySamples.compactMap {
            let bpm = $0.quantity.doubleValue(for: bpmUnit)
            return bpm > 0 ? (bpm, 60_000.0 / bpm) : nil
        }
        guard !rrPairs.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for (bpm, rrMs) in rrPairs {
                self.latestHeartRate = bpm
                self.sampleCount += 1
                self.recordSampleMilestoneIfNeeded()
                self.onRRInterval?(rrMs)
            }
        }
    }

    private func recordSampleMilestoneIfNeeded() {
        let milestones: Set<Int> = [1, 5, 10, 25, 50, 100]
        guard milestones.contains(sampleCount),
              !loggedSampleMilestones.contains(sampleCount) else { return }
        loggedSampleMilestones.insert(sampleCount)
        DiagnosticLog.shared.record(
            source: "watchOS",
            category: "healthKit",
            message: "Heart-rate samples received",
            metadata: [
                "samples": String(sampleCount),
                "latestHR": String(format: "%.0f", latestHeartRate)
            ])
    }
}

// MARK: - HKWorkoutSessionDelegate

extension HKWorkoutSessionManager: HKWorkoutSessionDelegate {
    nonisolated public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Self.log.info("HK_SESSION_STATE \(fromState.rawValue, privacy: .public)→\(toState.rawValue, privacy: .public)")
        DiagnosticLog.shared.record(
            source: "watchOS",
            category: "healthKit",
            message: "Workout session state changed",
            metadata: ["from": String(fromState.rawValue), "to": String(toState.rawValue)])
    }

    nonisolated public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Self.log.error("HK_SESSION_FAILED \(error.localizedDescription, privacy: .public)")
        DiagnosticLog.shared.record(
            source: "watchOS",
            category: "healthKit",
            level: .error,
            message: "Workout session failed",
            metadata: ["error": error.localizedDescription])
    }
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
            guard let self else { return }
            self.latestHeartRate = bpm
            self.sampleCount += 1
            self.recordSampleMilestoneIfNeeded()
            self.onRRInterval?(rrMs)
        }
    }
}
