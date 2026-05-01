import WatchKit
import Combine
import AmachBreatheShared

/// Fires haptic feedback synchronized to breath phase transitions.
/// Inhale onset → .directionUp; exhale onset → .directionDown.
///
/// `.start`/`.stop` were tried first but are imperceptible on Apple Watch SE
/// during normal wear — they're single very-brief ticks designed for workout
/// begin/end cues. `.directionUp`/`.directionDown` are two-tap patterns that
/// also semantically match rising-inhale / falling-exhale.
@MainActor
public final class HapticPacer {

    private var lastBreathPhase: BreathPhase?
    private var cancellable: AnyCancellable?

    public init(timer: MasterPhaseTimer) {
        cancellable = timer.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.handleState(state)
            }
    }

    /// Reset between-session state. Keeps the subscription alive — the
    /// `isActive` filter in `handleState` swallows idle ticks, and tearing
    /// down the cancellable here would silence haptics on every subsequent
    /// session (init is the only place we re-subscribe).
    public func stop() {
        lastBreathPhase = nil
    }

    // MARK: - Private

    private func handleState(_ state: PacerState) {
        // Reset on inactive so the next active phase plays a haptic on its
        // first inhale even if it matches the last seen breath phase.
        guard state.sessionPhase.isActive else {
            lastBreathPhase = nil
            return
        }

        let phase = state.breathPhase
        guard phase != lastBreathPhase else { return }
        lastBreathPhase = phase

        switch phase {
        case .inhale:
            WKInterfaceDevice.current().play(.directionUp)
        case .exhale:
            WKInterfaceDevice.current().play(.directionDown)
        }
    }
}
