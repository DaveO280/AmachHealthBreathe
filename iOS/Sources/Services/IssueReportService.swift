import Foundation
import UIKit
import AmachBreatheShared

@MainActor
final class IssueReportService {

    struct Snapshot: Codable {
        let generatedAt: Date
        let app: AppSnapshot
        let device: DeviceSnapshot
        let state: StateSnapshot
        let recentSessions: [SessionRecord]
        let diagnostics: [DiagnosticEvent]
    }

    struct AppSnapshot: Codable {
        let version: String
        let build: String
        let bundleIdentifier: String
        let receiptEnvironment: String
    }

    struct DeviceSnapshot: Codable {
        let model: String
        let systemName: String
        let systemVersion: String
        let idiom: String
    }

    struct StateSnapshot: Codable {
        let watchReachable: Bool
        let syncError: String?
        let isSyncing: Bool
        let isRestoring: Bool
        let subscriptionState: String
        let defaultRatio: String
        let companionAudioEnabled: Bool
        let pacerStyle: String
    }

    func createReport(
        settings: AppSettings,
        sessions: [SessionRecord],
        sessionService: SessionService,
        subscriptionService: SubscriptionService,
        watchService: WatchConnectivityService
    ) throws -> URL {
        DiagnosticLog.shared.record(
            source: "iOS",
            category: "issueReport",
            message: "Issue report generated")

        let snapshot = Snapshot(
            generatedAt: Date(),
            app: appSnapshot(),
            device: deviceSnapshot(),
            state: StateSnapshot(
                watchReachable: watchService.isWatchReachable,
                syncError: sessionService.syncError,
                isSyncing: sessionService.isSyncing,
                isRestoring: sessionService.isRestoring,
                subscriptionState: String(describing: subscriptionService.state),
                defaultRatio: settings.defaultRatio.rawValue,
                companionAudioEnabled: settings.watchCompanionAudioTrackingEnabled,
                pacerStyle: String(describing: settings.pacerStyle)
            ),
            recentSessions: Array(sessions.prefix(5)),
            diagnostics: DiagnosticLog.shared.snapshot()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AmachBreathe-IssueReport-\(stamp).json")
        try data.write(to: url, options: [.atomic])
        return url
    }

    private func appSnapshot() -> AppSnapshot {
        let bundle = Bundle.main
        return AppSnapshot(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            bundleIdentifier: bundle.bundleIdentifier ?? "unknown",
            receiptEnvironment: bundle.appStoreReceiptURL?.lastPathComponent ?? "unknown"
        )
    }

    private func deviceSnapshot() -> DeviceSnapshot {
        let device = UIDevice.current
        return DeviceSnapshot(
            model: device.model,
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            idiom: UIDevice.current.userInterfaceIdiom.displayName
        )
    }
}

private extension UIUserInterfaceIdiom {
    var displayName: String {
        switch self {
        case .phone: return "phone"
        case .pad: return "pad"
        case .tv: return "tv"
        case .carPlay: return "carPlay"
        case .mac: return "mac"
        case .vision: return "vision"
        case .unspecified: return "unspecified"
        @unknown default: return "unknown"
        }
    }
}
