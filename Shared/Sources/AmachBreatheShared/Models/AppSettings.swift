import Foundation

/// User-configurable app settings. Codable for UserDefaults persistence.
public struct AppSettings: Codable, Sendable, Equatable {

    public var defaultRatio: BreathRatio
    /// Stored as seconds since midnight for each reminder.
    public var reminderSecondsFromMidnight: [Int]
    /// 0.0 – 1.0
    public var audioVolume: Double
    public var pacerStyle: PacerStyle

    public enum PacerStyle: String, Codable, CaseIterable, Sendable {
        case ring    = "ring"      // expanding ring (default)
        case text    = "text"      // in / out text cue
        case minimal = "minimal"   // countdown timer only
    }

    public static let `default` = AppSettings(
        defaultRatio: .fourToSix,
        reminderSecondsFromMidnight: [],
        audioVolume: 0.5,
        pacerStyle: .ring
    )

    public init(
        defaultRatio: BreathRatio,
        reminderSecondsFromMidnight: [Int],
        audioVolume: Double,
        pacerStyle: PacerStyle
    ) {
        self.defaultRatio = defaultRatio
        self.reminderSecondsFromMidnight = reminderSecondsFromMidnight
        self.audioVolume = audioVolume
        self.pacerStyle = pacerStyle
    }
}
