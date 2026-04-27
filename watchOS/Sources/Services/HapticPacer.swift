import WatchKit
import Combine
import AmachBreatheShared

/// Fires haptic feedback synchronized to breath phase transitions.
/// Inhale onset → .start; exhale onset → .stop.
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

    public func stop() {
        cancellable = nil
        lastBreathPhase = nil
    }

    // MARK: - Private

    private func handleState(_ state: PacerState) {
        guard state.sessionPhase.isActive else { return }

        let phase = state.breathPhase
        guard phase != lastBreathPhase else { return }
        lastBreathPhase = phase

        switch phase {
        case .inhale:
            WKInterfaceDevice.current().play(.start)
        case .exhale:
            WKInterfaceDevice.current().play(.stop)
        }
    }
}
