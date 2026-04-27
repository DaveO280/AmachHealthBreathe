import Foundation
import AmachBreatheShared

/// Published at 60 Hz by MasterPhaseTimer; all pacers read from this single source of truth.
public struct PacerState: Sendable {
    public let sessionPhase: SessionPhase
    public let breathPhase: BreathPhase
    /// 0…1 within the current breath phase (inhale or exhale)
    public let breathProgress: Double
    /// Scale factor for the expanding ring: 0.6 (min) … 1.4 (max), sinusoidal
    public let ringScale: Double
    public let totalElapsed: TimeInterval
    public let sessionPhaseElapsed: TimeInterval
    public let sessionPhaseRemaining: TimeInterval?

    public static let idle = PacerState(
        sessionPhase: .idle,
        breathPhase: .inhale,
        breathProgress: 0,
        ringScale: 1.0,
        totalElapsed: 0,
        sessionPhaseElapsed: 0,
        sessionPhaseRemaining: nil
    )
}
