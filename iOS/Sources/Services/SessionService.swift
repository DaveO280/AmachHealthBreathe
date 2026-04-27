import Foundation
import AmachBreatheShared

/// Persists BreathingSessionRecords locally (UserDefaults) and uploads them
/// to Storj via AmachAPIClient when a wallet key is available.
@MainActor
public final class SessionService: ObservableObject {

    @Published public private(set) var sessions: [SessionRecord] = []
    @Published public private(set) var isSyncing = false
    @Published public private(set) var isRestoring = false
    @Published public private(set) var syncError: String?

    private let storageKey = "com.amach.breathe.sessions"
    private let apiClient = AmachAPIClient()

    public init() {
        loadFromDisk()
    }

    // MARK: - Public

    public func save(_ record: BreathingSessionRecord) {
        guard !sessions.contains(where: { $0.id == record.id }) else { return }
        let sr = SessionRecord(from: record)
        sessions.insert(sr, at: 0)
        persistToDisk()
    }

    /// Upload pending sessions + post dashboard timeline events. Call after wallet connects.
    public func syncPending(encryptionKey: WalletEncryptionKey) async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        var hadError = false
        for i in sessions.indices where sessions[i].uploadStatus == .pending {
            let record = sessions[i].breathingSession
            do {
                let result = try await apiClient.storeBreathingSession(
                    record: record,
                    walletAddress: encryptionKey.walletAddress,
                    encryptionKey: encryptionKey
                )
                sessions[i].uploadStatus = .uploaded
                sessions[i].storjUri = result.storjUri

                // Best-effort dashboard event — don't fail the upload if this errors
                try? await apiClient.postBreathingSessionEvent(
                    record: record,
                    walletAddress: encryptionKey.walletAddress,
                    encryptionKey: encryptionKey
                )
            } catch {
                sessions[i].uploadStatus = .failed
                hadError = true
            }
        }
        if hadError { syncError = "Some sessions failed to sync. Tap to retry." }
        persistToDisk()
    }

    /// Restores session history from Storj for a new device install.
    /// Merges cloud records with any existing local records (deduplicates by id).
    public func restoreFromStorj(encryptionKey: WalletEncryptionKey) async throws {
        isRestoring = true
        defer { isRestoring = false }

        let items = try await apiClient.listBreathingSessions(
            walletAddress: encryptionKey.walletAddress,
            encryptionKey: encryptionKey
        )

        var restored: [SessionRecord] = []
        for item in items {
            guard !sessions.contains(where: { $0.storjUri == item.uri }) else { continue }
            do {
                let record = try await apiClient.retrieveBreathingSession(
                    storjUri: item.uri,
                    walletAddress: encryptionKey.walletAddress,
                    encryptionKey: encryptionKey
                )
                // Skip if we already have this session by id
                guard !sessions.contains(where: { $0.id == record.id }) else { continue }
                var sr = SessionRecord(from: record, uploadStatus: .uploaded, storjUri: item.uri)
                restored.append(sr)
            } catch {
                continue
            }
        }

        if !restored.isEmpty {
            sessions = (sessions + restored).sorted { $0.breathingSession.timestamp > $1.breathingSession.timestamp }
            persistToDisk()
        }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data) else { return }
        sessions = decoded
    }

    private func persistToDisk() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
