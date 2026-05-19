import Foundation
import AmachBreatheShared

/// Tracks iPhone mic audio while an Apple Watch session runs, keyed by `sessionId`.
/// Metrics are merged into the watch `BreathingSessionRecord` on `sessionComplete`.
///
/// MVP constraints: phone app foreground/nearby, no background audio mode.
/// Phase gating uses watch `sessionPhaseHint` messages; until `mainStarted`, the mic
/// runs but samples are not analyzed (same as iPhone-only sessions).
@MainActor
final class WatchCompanionAudioService: ObservableObject {

    @Published private(set) var showPermissionDeniedAlert = false

    private let tracker = iPhoneAudioBreathTracker()
    private var activeSessionId: String?
    private var mergedSessionIds = Set<String>()
    /// Phone-initiated watch start with companion enabled before `sessionStarted` arrives.
    private var armedSessionId: String?
    private var armedBPM: Double = 0
    private var settingsCompanionEnabled = false

    func setCompanionEnabledInSettings(_ enabled: Bool) {
        settingsCompanionEnabled = enabled
        if !enabled {
            cancelTracking()
            armedSessionId = nil
        }
    }

    /// Called when the user starts a session on the watch from the phone.
    func armForPhoneInitiatedWatchStart(sessionId: String, bpm: Double, companionEnabled: Bool) {
        armedSessionId = companionEnabled ? sessionId : nil
        armedBPM = bpm
        if companionEnabled {
            Task { await beginTracking(sessionId: sessionId, targetBPM: bpm) }
        } else {
            cancelTracking()
        }
    }

    func handleSessionStarted(_ message: SessionStartedMessage) {
        guard shouldTrackCompanion(
            sessionId: message.sessionId,
            explicitCompanionFromStart: armedSessionId == message.sessionId
        ) else { return }

        armedSessionId = nil
        Task { await beginTracking(sessionId: message.sessionId, targetBPM: message.bpm) }
    }

    func handlePhaseHint(_ hint: SessionPhaseHintMessage) {
        guard activeSessionId == hint.sessionId else { return }
        switch hint.phase {
        case .mainStarted:
            tracker.setAnalysisActive(true)
        case .sessionEnded:
            tracker.setAnalysisActive(false)
        }
    }

    func handleSessionCancelled() {
        cancelTracking()
        armedSessionId = nil
    }

    /// Stops tracking and returns metrics for merge. Idempotent per `sessionId`.
    func takeMetricsForMerge(sessionId: String) -> AudioBreathMetrics? {
        guard !mergedSessionIds.contains(sessionId) else { return nil }
        guard activeSessionId == sessionId || armedSessionId == sessionId else { return nil }

        let metrics: AudioBreathMetrics?
        if activeSessionId == sessionId {
            metrics = tracker.finishMetrics()
            activeSessionId = nil
        } else {
            metrics = nil
        }
        armedSessionId = nil
        mergedSessionIds.insert(sessionId)
        return metrics
    }

    func dismissPermissionAlert() {
        showPermissionDeniedAlert = false
    }

    // MARK: - Private

    private func shouldTrackCompanion(sessionId: String, explicitCompanionFromStart: Bool) -> Bool {
        explicitCompanionFromStart || settingsCompanionEnabled
    }

    private func beginTracking(sessionId: String, targetBPM: Double) async {
        if activeSessionId == sessionId { return }
        if let previous = activeSessionId, previous != sessionId {
            _ = tracker.finishMetrics()
        }
        activeSessionId = sessionId
        tracker.setAnalysisActive(false)
        await tracker.start(targetBPM: targetBPM)
        if tracker.status == .denied {
            showPermissionDeniedAlert = true
            activeSessionId = nil
            return
        }
        if activeSessionId != sessionId {
            tracker.stop()
        }
    }

    private func cancelTracking() {
        tracker.stop()
        activeSessionId = nil
    }
}
