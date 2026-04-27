// SharedModels.swift — common model types shared across iOS + watchOS + Networking

import Foundation

// MARK: - Wallet Encryption Key (matches web app wire format)

public struct WalletEncryptionKey: Codable, Sendable {
    public let walletAddress: String
    public let encryptionKey: String
    public let signature: String
    public let timestamp: Int

    public init(walletAddress: String, encryptionKey: String, signature: String, timestamp: Int) {
        self.walletAddress = walletAddress
        self.encryptionKey = encryptionKey
        self.signature = signature
        self.timestamp = timestamp
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: WebKeys.self)
        try c.encode(walletAddress, forKey: .walletAddress)
        try c.encode(encryptionKey, forKey: .key)
        try c.encode(signature,     forKey: .signature)
        try c.encode(timestamp,     forKey: .derivedAt)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FlexKeys.self)
        walletAddress = try c.decode(String.self, forKey: .walletAddress)
        if let key = try? c.decode(String.self, forKey: .key) {
            encryptionKey = key
        } else {
            encryptionKey = try c.decode(String.self, forKey: .encryptionKey)
        }
        signature = (try? c.decode(String.self, forKey: .signature)) ?? ""
        if let derivedAt = try? c.decode(Int.self, forKey: .derivedAt) {
            timestamp = derivedAt
        } else if let ts = try? c.decode(Int.self, forKey: .timestamp) {
            timestamp = ts
        } else {
            timestamp = Int(Date().timeIntervalSince1970 * 1000)
        }
    }

    private enum WebKeys: String, CodingKey {
        case walletAddress, key, signature, derivedAt
    }

    private enum FlexKeys: String, CodingKey {
        case walletAddress, key, encryptionKey, signature, derivedAt, timestamp
    }
}

// MARK: - API Errors

public enum APIError: LocalizedError, Sendable {
    case invalidResponse
    case httpError(statusCode: Int)
    case requestFailed(String)
    case encodingFailed
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:         return "Invalid response from server"
        case .httpError(let code):     return "HTTP error: \(code)"
        case .requestFailed(let msg):  return msg
        case .encodingFailed:          return "Failed to encode request"
        case .decodingFailed:          return "Failed to decode response"
        }
    }
}

// MARK: - Storj Wire Types

public struct StorjStoreOptions: Encodable, Sendable {
    public let metadata: [String: String]
    public init(metadata: [String: String]) { self.metadata = metadata }
}

public struct AnyCodable: Encodable, Sendable {
    private let _encode: @Sendable (Encoder) throws -> Void

    public init<T: Encodable & Sendable>(_ value: T) {
        _encode = { try value.encode(to: $0) }
    }

    public func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

public struct StorjRequest: Encodable, Sendable {
    public let action: String
    public let userAddress: String
    public let encryptionKey: WalletEncryptionKey
    public let data: AnyCodable
    public let dataType: String
    public let options: StorjStoreOptions?
}

public struct StorjListRequest: Encodable, Sendable {
    public let action: String
    public let userAddress: String
    public let encryptionKey: WalletEncryptionKey
    public let dataType: String?
}

public struct StorjRetrieveRequest: Encodable, Sendable {
    public let action: String
    public let userAddress: String
    public let encryptionKey: WalletEncryptionKey
    public let storjUri: String
}

public struct StorjResponse<T: Decodable>: Decodable, Sendable where T: Sendable {
    public let success: Bool
    public let result: T?
    public let error: String?
}

public struct StorjStoreResult: Decodable, Sendable {
    public let storjUri: String
    public let contentHash: String
    public let size: Int?
}

public struct StorjRetrievedData<T: Decodable>: Decodable, Sendable where T: Sendable {
    public let data: T
    public let storjUri: String?
    public let contentHash: String?
    public let verified: Bool?
}

public struct StorjListItem: Decodable, Identifiable, Sendable {
    public var id: String { uri }
    public let uri: String
    public let contentHash: String
    public let size: Int
    public let uploadedAt: TimeInterval
    public let dataType: String
    public let metadata: [String: String]?

    public var uploadDate: Date { Date(timeIntervalSince1970: uploadedAt / 1000) }
    public var tier: String? { metadata?["tier"] }
}

// MARK: - Breathing Session Record

/// On-Storj record for a completed breathing session.
/// Stored at: <userPrefix>/breathing/<sessionId>.json
public struct BreathingSessionRecord: Codable, Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let durationSeconds: Int
    public let bpm: Double
    public let ratio: String               // e.g. "1:1", "4:6"
    public let baselineHRV: Double         // ms
    public let recoveryHRV: Double         // ms
    public let avgHRV: Double              // ms
    public let coherenceScore: Double      // 0–1
    public let reflectionRating: Int?      // 1–5, nil if skipped

    public init(
        id: String = UUID().uuidString,
        timestamp: Date,
        durationSeconds: Int,
        bpm: Double,
        ratio: String,
        baselineHRV: Double,
        recoveryHRV: Double,
        avgHRV: Double,
        coherenceScore: Double,
        reflectionRating: Int? = nil
    ) {
        self.id               = id
        self.timestamp        = timestamp
        self.durationSeconds  = durationSeconds
        self.bpm              = bpm
        self.ratio            = ratio
        self.baselineHRV      = baselineHRV
        self.recoveryHRV      = recoveryHRV
        self.avgHRV           = avgHRV
        self.coherenceScore   = coherenceScore
        self.reflectionRating = reflectionRating
    }
}

// MARK: - Breathing Session Timeline Event
// Matches Amach dashboard's BREATHING_SESSION event type (committed in healthEventTypes.ts Phase 0).
// Stored as dataType:"timeline-event" in Storj so the Amach dashboard picks it up automatically.

public struct BreathingSessionEvent: Codable, Sendable {
    public struct Metadata: Codable, Sendable {
        public let platform: String
        public let version: String
        public let source: String
    }
    public let id: String
    public let eventType: String           // "BREATHING_SESSION"
    public let timestamp: Date
    public let data: [String: String]
    public let metadata: Metadata

    public init(from record: BreathingSessionRecord, platform: String = "ios") {
        self.id = UUID().uuidString
        self.eventType = "BREATHING_SESSION"
        self.timestamp = record.timestamp
        self.data = [
            "sessionId":       record.id,
            "durationSeconds": String(record.durationSeconds),
            "bpm":             String(record.bpm),
            "ratio":           record.ratio,
            "coherenceScore":  String(format: "%.3f", record.coherenceScore),
            "avgHRV":          String(format: "%.1f", record.avgHRV),
            "baselineHRV":     String(format: "%.1f", record.baselineHRV),
            "recoveryHRV":     String(format: "%.1f", record.recoveryHRV)
        ]
        self.metadata = Metadata(platform: platform, version: "1", source: "user")
    }
}

// MARK: - Generic tracking response

public struct TrackingResponse: Decodable, Sendable {
    public let success: Bool?
    public let error: String?
}

// MARK: - Subscription State

public enum SubscriptionState: String, Codable, Sendable {
    case trial
    case subscribed
    case connected   // free via 3+ sessions synced in last 30 days
    case expired
}
