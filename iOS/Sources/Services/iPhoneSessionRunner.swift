import Foundation
import Combine
import AmachBreatheShared

/// Orchestrates an iPhone-only breathing session (no HRV collection).
/// Mirrors the structure of WatchSessionRunner but drives audio + haptics
/// via iOS APIs and saves a BreathingSessionRecord with source:.phone.
@MainActor
final class iPhoneSessionRunner: ObservableObject {

    // MARK: - Published state

    @Published private(set) var phase: SessionPhase = .idle
    @Published private(set) var pacerState: PacerState = .idle
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isPaused:  Bool = false
    @Published private(set) var completedRecord: BreathingSessionRecord?

    /// Called when a session finishes (reflection submitted or skipped).
    var onSessionComplete: ((BreathingSessionRecord) -> Void)?

    // MARK: - Sub-services

    let timer = iPhoneMasterPhaseTimer()
    private var audioPacer: iPhoneAudioPacer?

    // MARK: - Session config

    private var bpm: Double = 6.0
    private var selectedRatio: BreathRatio = .fourToSix
    private var mainDurationSeconds: Int = 300
    private var sessionId: String = ""
    private var reflectionRating: Int?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() { subscribeToTimer() }

    // MARK: - Public API

    func startSession(bpm: Double, durationSeconds: Int, ratio: BreathRatio) {
        self.bpm = bpm
        self.selectedRatio = ratio
        self.mainDurationSeconds = durationSeconds
        self.sessionId = UUID().uuidString
        self.reflectionRating = nil
        completedRecord = nil

        audioPacer = iPhoneAudioPacer(timer: timer)
        timer.start(bpm: bpm, mainDurationSeconds: durationSeconds, ratio: ratio)
        isRunning = true
        isPaused = false
        AmachHaptics.buttonPress()
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        timer.pause()
        isPaused = true
        AmachHaptics.toggle()
    }

    func resume() {
        guard isRunning, isPaused else { return }
        timer.resume()
        isPaused = false
        AmachHaptics.toggle()
    }

    /// Called from the reflection view when the user rates or skips.
    func submitReflection(rating: Int?) {
        reflectionRating = rating
        buildRecord()
        phase = .complete
    }

    /// Called when the user taps Done on the completion screen.
    func endSession() {
        audioPacer?.stop()
        audioPacer = nil
        timer.stop()
        isRunning = false
        isPaused = false
        phase = .idle
        pacerState = .idle
    }

    // MARK: - Timer observation

    private func subscribeToTimer() {
        timer.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.handleTimerState(state) }
            .store(in: &cancellables)
    }

    private func handleTimerState(_ state: PacerState) {
        pacerState = state
        let prevPhase = phase

        // Don't let the timer override .complete — the user or submitReflection owns that.
        if case .complete = phase { return }

        phase = state.sessionPhase

        // Capture phase transitions
        if prevPhase != state.sessionPhase {
            switch state.sessionPhase {
            case .complete:
                // Timer reached end without user submitting reflection — build with nil rating.
                if reflectionRating == nil { buildRecord() }
                phase = .complete
                AmachHaptics.success()
            default:
                break
            }
        }
    }

    // MARK: - Build result

    private func buildRecord() {
        guard completedRecord == nil else { return }
        let record = BreathingSessionRecord(
            id: sessionId,
            timestamp: Date(),
            durationSeconds: mainDurationSeconds,
            bpm: bpm,
            ratio: selectedRatio.rawValue,
            reflectionRating: reflectionRating,
            source: .phone
        )
        completedRecord = record
        onSessionComplete?(record)
    }
}
