// AmachAPIClient.swift
// AmachBreatheShared — lifted from AmachHealth-iOS
//
// Communicates with the Amach web backend (/api/storj, /api/health, etc.)
// Shared by iOS and watchOS targets via the AmachBreatheShared package.

import Foundation

// MARK: - Client

public final class AmachAPIClient: Sendable {

    public static let shared = AmachAPIClient()

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL? = nil) {
        let urlString = baseURL?.absoluteString
            ?? ProcessInfo.processInfo.environment["AMACH_API_URL"]
            ?? "https://www.amachhealth.com"
        self.baseURL = URL(string: urlString)!

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    // MARK: - Storj: Store

    public func storeBreathingSession(
        record: BreathingSessionRecord,
        walletAddress: String,
        encryptionKey: WalletEncryptionKey
    ) async throws -> StorjStoreResult {
        let request = StorjRequest(
            action: "storage/store",
            userAddress: walletAddress,
            encryptionKey: encryptionKey,
            data: AnyCodable(record),
            dataType: "breathing-session",
            options: StorjStoreOptions(metadata: [
                "sessionId":      record.id,
                "timestamp":      ISO8601DateFormatter().string(from: record.timestamp),
                "bpm":            String(record.bpm),
                "coherenceScore": String(record.coherenceScore),
                "platform":       "ios"
            ])
        )
        return try await post(path: "/api/storj", body: request, responseType: StorjResponse<StorjStoreResult>.self)
            .unwrapped()
    }

    // MARK: - Storj: List

    public func listBreathingSessions(
        walletAddress: String,
        encryptionKey: WalletEncryptionKey
    ) async throws -> [StorjListItem] {
        let request = StorjListRequest(
            action: "storage/list",
            userAddress: walletAddress,
            encryptionKey: encryptionKey,
            dataType: "breathing-session"
        )
        return try await post(path: "/api/storj", body: request, responseType: StorjResponse<[StorjListItem]>.self)
            .unwrapped()
    }

    // MARK: - Storj: Retrieve

    public func retrieveBreathingSession(
        storjUri: String,
        walletAddress: String,
        encryptionKey: WalletEncryptionKey
    ) async throws -> BreathingSessionRecord {
        let request = StorjRetrieveRequest(
            action: "storage/retrieve",
            userAddress: walletAddress,
            encryptionKey: encryptionKey,
            storjUri: storjUri
        )
        let envelope = try await post(
            path: "/api/storj",
            body: request,
            responseType: StorjResponse<StorjRetrievedData<BreathingSessionRecord>>.self
        ).unwrapped()
        return envelope.data
    }

    // MARK: - Subscription state (stored in Storj for cross-device sync)

    public func storeSubscriptionState(
        record: SubscriptionRecord,
        encryptionKey: WalletEncryptionKey
    ) async throws {
        let request = StorjRequest(
            action: "storage/store",
            userAddress: record.walletAddress,
            encryptionKey: encryptionKey,
            data: AnyCodable(record),
            dataType: "subscription-state",
            options: StorjStoreOptions(metadata: [
                "state":     record.state.rawValue,
                "updatedAt": ISO8601DateFormatter().string(from: record.updatedAt)
            ])
        )
        _ = try await post(path: "/api/storj", body: request,
                           responseType: StorjResponse<StorjStoreResult>.self)
    }

    public func retrieveSubscriptionState(
        walletAddress: String,
        encryptionKey: WalletEncryptionKey
    ) async throws -> SubscriptionRecord? {
        // List subscription-state items, take the most recent
        let items = try await post(
            path: "/api/storj",
            body: StorjListRequest(action: "storage/list", userAddress: walletAddress,
                                   encryptionKey: encryptionKey, dataType: "subscription-state"),
            responseType: StorjResponse<[StorjListItem]>.self
        ).unwrapped()

        guard let latest = items.sorted(by: { $0.uploadedAt > $1.uploadedAt }).first else {
            return nil
        }
        let envelope = try await post(
            path: "/api/storj",
            body: StorjRetrieveRequest(action: "storage/retrieve", userAddress: walletAddress,
                                       encryptionKey: encryptionKey, storjUri: latest.uri),
            responseType: StorjResponse<StorjRetrievedData<SubscriptionRecord>>.self
        ).unwrapped()
        return envelope.data
    }

    // MARK: - Cost telemetry (/api/tracking)

    public func submitTelemetry(
        _ event: SubscriptionTelemetryEvent,
        encryptionKey: WalletEncryptionKey
    ) async throws {
        // /api/tracking accepts any JSON body — we send the event directly.
        // No authentication required; the backend proxies to the admin analytics API.
        let _ = try await post(path: "/api/tracking", body: event,
                               responseType: TrackingResponse.self)
    }

    // MARK: - Timeline: Post BREATHING_SESSION event

    /// Posts a BREATHING_SESSION timeline event so the record appears in the Amach dashboard.
    /// Fails silently — dashboard visibility is a best-effort side-effect of session upload.
    public func postBreathingSessionEvent(
        record: BreathingSessionRecord,
        walletAddress: String,
        encryptionKey: WalletEncryptionKey,
        platform: String = "ios"
    ) async throws {
        let event = BreathingSessionEvent(from: record, platform: platform)
        let request = StorjRequest(
            action: "storage/store",
            userAddress: walletAddress,
            encryptionKey: encryptionKey,
            data: AnyCodable(event),
            dataType: "timeline-event",
            options: StorjStoreOptions(metadata: [
                "eventId":   event.id,
                "eventType": event.eventType,
                "timestamp": ISO8601DateFormatter().string(from: event.timestamp),
                "platform":  platform
            ])
        )
        _ = try await post(path: "/api/storj", body: request,
                           responseType: StorjResponse<StorjStoreResult>.self)
    }

    // MARK: - HTTP Core

    func post<B: Encodable, R: Decodable>(
        path: String,
        body: B,
        responseType: R.Type = R.self
    ) async throws -> R {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.requestFailed("Invalid path: \(path)")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            req.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw APIError.encodingFailed
        }

        let (data, response) = try await session.data(for: req)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.httpError(statusCode: http.statusCode)
        }

        do {
            return try JSONDecoder().decode(R.self, from: data)
        } catch {
            throw APIError.decodingFailed
        }
    }
}

// MARK: - StorjResponse convenience

extension StorjResponse {
    func unwrapped() throws -> T {
        guard success, let result else {
            throw APIError.requestFailed(error ?? "Unknown API error")
        }
        return result
    }
}
