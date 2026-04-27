import Foundation
import AmachBreatheShared

public enum SessionPhase: Equatable, Sendable {
    case idle
    case baseline                   // 30 s — collect resting HRV
    case warmup                     // 60 s — slow into target BPM
    case main(durationSeconds: Int) // 5/10/15 min user-selected
    case recovery                   // 30 s — cool-down
    case reflection                 // rating 1–5
    case complete

    public var targetDurationSeconds: Int? {
        switch self {
        case .baseline:              return 30
        case .warmup:                return 60
        case .main(let d):           return d
        case .recovery:              return 30
        case .idle, .reflection, .complete: return nil
        }
    }

    public var isActive: Bool {
        switch self {
        case .baseline, .warmup, .main, .recovery: return true
        default: return false
        }
    }
}

public enum BreathPhase: String, Sendable {
    case inhale, exhale
}
