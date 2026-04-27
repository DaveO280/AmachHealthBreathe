import Foundation

// MARK: - Complication state

public enum ComplicationState: String, Sendable, Equatable, CaseIterable {
    case idle       // needs calibration, or subscription expired
    case ready      // calibrated and subscription active — tap to breathe
    case inSession  // session currently running on Watch
}

// MARK: - Pure display logic (testable without WidgetKit)

public enum ComplicationDisplayLogic {

    public struct DisplayInfo: Sendable, Equatable {
        public let iconName: String
        public let label: String
        public let accentColorHex: String

        public init(iconName: String, label: String, accentColorHex: String) {
            self.iconName = iconName
            self.label = label
            self.accentColorHex = accentColorHex
        }
    }

    public static func displayInfo(
        complicationState: ComplicationState,
        subscriptionState: SubscriptionState
    ) -> DisplayInfo {
        switch complicationState {
        case .inSession:
            return DisplayInfo(
                iconName: "lungs.fill",
                label: "Active",
                accentColorHex: "10B981"  // green
            )
        case .ready:
            return DisplayInfo(
                iconName: "waveform.path.ecg.rectangle",
                label: "Breathe",
                accentColorHex: "6366F1"  // amachPrimary
            )
        case .idle:
            switch subscriptionState {
            case .expired:
                return DisplayInfo(
                    iconName: "exclamationmark.circle",
                    label: "Expired",
                    accentColorHex: "EF4444"  // red
                )
            case .trial, .connected:
                return DisplayInfo(
                    iconName: "waveform.path.ecg",
                    label: "Setup",
                    accentColorHex: "9CA3AF"  // gray
                )
            case .subscribed:
                return DisplayInfo(
                    iconName: "waveform.path.ecg",
                    label: "Setup",
                    accentColorHex: "9CA3AF"
                )
            }
        }
    }

    // MARK: - State derivation from UserDefaults (shared key names)

    public static let inSessionKey    = "com.amach.breathe.complication.inSession"
    public static let hasCalibrationKey = "com.amach.breathe.complication.hasCalibration"
    public static let subscriptionKey = "com.amach.breathe.subscriptionState"

    public static func complicationState(inSession: Bool, hasCalibration: Bool) -> ComplicationState {
        if inSession { return .inSession }
        if hasCalibration { return .ready }
        return .idle
    }
}
