import Foundation

/// Inhale : exhale timing ratio for the resonance breathing pacer.
public enum BreathRatio: String, Codable, CaseIterable, Sendable {
    case oneToOne = "1:1"   // 50 % inhale / 50 % exhale — balanced
    case fourToSix = "4:6"  // 40 % inhale / 60 % exhale — default resonance ratio

    public var inhaleFraction: Double {
        switch self {
        case .oneToOne:  return 0.5
        case .fourToSix: return 0.4
        }
    }

    public var exhaleFraction: Double { 1.0 - inhaleFraction }

    public var displayLabel: String { rawValue }
}
