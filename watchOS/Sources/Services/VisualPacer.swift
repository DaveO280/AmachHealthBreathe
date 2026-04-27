import SwiftUI
import Combine
import AmachBreatheShared

/// Provides the animated ring scale from MasterPhaseTimer state.
/// Views read `ringScale` directly from `PacerState.ringScale`.
/// This class exists as a named seam for future visual customization.
@MainActor
public final class VisualPacer: ObservableObject {

    @Published public private(set) var ringScale: Double = 1.0
    @Published public private(set) var breathPhase: BreathPhase = .inhale
    @Published public private(set) var breathProgress: Double = 0

    private var cancellable: AnyCancellable?

    public init(timer: MasterPhaseTimer) {
        cancellable = timer.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.ringScale = state.ringScale
                self?.breathPhase = state.breathPhase
                self?.breathProgress = state.breathProgress
            }
    }
}
