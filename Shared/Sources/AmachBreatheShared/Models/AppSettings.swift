import Foundation

/// User-configurable app settings. Codable for UserDefaults persistence.
public struct AppSettings: Codable, Sendable, Equatable {

    public var defaultRatio: BreathRatio
    /// Stored as seconds since midnight for each reminder.
    public var reminderSecondsFromMidnight: [Int]
    /// 0.0 – 1.0
    public var audioVolume: Double
    public var pacerStyle: PacerStyle
    /// When true, iPhone mic tracks breath audio during Apple Watch sessions (companion mode).
    public var watchCompanionAudioTrackingEnabled: Bool

    public enum PacerStyle: String, Codable, CaseIterable, Sendable {
        case ring    = "ring"      // expanding ring (default)
        case text    = "text"      // in / out text cue
        case minimal = "minimal"   // countdown timer only
    }

    public static let `default` = AppSettings(
        defaultRatio: .fourToSix,
        reminderSecondsFromMidnight: [],
        audioVolume: 0.5,
        pacerStyle: .ring,
        watchCompanionAudioTrackingEnabled: false
    )

    public init(
        defaultRatio: BreathRatio,
        reminderSecondsFromMidnight: [Int],
        audioVolume: Double,
        pacerStyle: PacerStyle,
        watchCompanionAudioTrackingEnabled: Bool = false
    ) {
        self.defaultRatio = defaultRatio
        self.reminderSecondsFromMidnight = reminderSecondsFromMidnight
        self.audioVolume = audioVolume
        self.pacerStyle = pacerStyle
        self.watchCompanionAudioTrackingEnabled = watchCompanionAudioTrackingEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultRatio = try c.decode(BreathRatio.self, forKey: .defaultRatio)
        reminderSecondsFromMidnight = try c.decode([Int].self, forKey: .reminderSecondsFromMidnight)
        audioVolume = try c.decode(Double.self, forKey: .audioVolume)
        pacerStyle = try c.decode(PacerStyle.self, forKey: .pacerStyle)
        watchCompanionAudioTrackingEnabled = try c.decodeIfPresent(
            Bool.self, forKey: .watchCompanionAudioTrackingEnabled) ?? false
    }
}
