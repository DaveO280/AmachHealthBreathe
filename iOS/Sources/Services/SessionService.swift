import Foundation
import AmachBreatheShared

/// Persists BreathingSessionRecords locally (UserDefaults) and uploads them
/// to Storj via AmachAPIClient when a wallet key is available.
@MainActor
public final class SessionService: ObservableObject {

    @Published public private(set) var sessions: [SessionRecord] = []

    private let storageKey = "com.amach.breathe.sessions"
    private let apiClient = AmachAPIClient()

    public init() {
        loadFromDisk()
    }

    // MARK: - Public

    public func save(_ record: BreathingSessionRecord) {
        let sr = SessionRecord(from: record)
        sessions.insert(sr, at: 0)
        persistToDisk()
    }

    /// Attempt to upload any pending sessions. Call after wallet is connected.
    public func syncPending(walletAddress: String, encryptionKey: String) async {
        for i in sessions.indices where sessions[i].uploadStatus == .pending {
            let record = sessions[i].breathingSession
            do {
                let key = WalletEncryptionKey(
                    walletAddress: walletAddress,
                    encryptionKey: encryptionKey,
                    signature: "",
                    timestamp: Int(Date().timeIntervalSince1970)
                )
                _ = try await apiClient.storeBreathingSession(
                    record: record,
                    walletAddress: walletAddress,
                    encryptionKey: key
                )
                sessions[i].uploadStatus = .uploaded
            } catch {
                sessions[i].uploadStatus = .failed
            }
        }
        persistToDisk()
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
