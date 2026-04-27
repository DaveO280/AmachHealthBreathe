import Foundation
import AmachBreatheShared

@MainActor
public final class AppSettingsService: ObservableObject {

    @Published public private(set) var settings: AppSettings = .default

    private let key = "com.amach.breathe.appSettings"

    public init() {
        load()
    }

    public func update(_ settings: AppSettings) {
        self.settings = settings
        persist()
    }

    public func updateRatio(_ ratio: BreathRatio) {
        settings.defaultRatio = ratio
        persist()
    }

    public func updateVolume(_ volume: Double) {
        settings.audioVolume = max(0, min(1, volume))
        persist()
    }

    public func updatePacerStyle(_ style: AppSettings.PacerStyle) {
        settings.pacerStyle = style
        persist()
    }

    public func updateReminders(_ secondsFromMidnight: [Int]) {
        settings.reminderSecondsFromMidnight = secondsFromMidnight
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return }
        settings = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
