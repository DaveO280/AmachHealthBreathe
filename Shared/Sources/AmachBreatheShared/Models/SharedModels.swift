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

// MARK: - Session Source

public enum SessionSource: String, Codable, Sendable {
    case watch
    case phone
}

// MARK: - Audio Breath Tracking

public enum AudioBreathDataQuality: String, Codable, Sendable {
    case unavailable
    case low
    case fair
    case good
}

/// Derived, on-device metrics from optional iPhone microphone tracking.
/// Raw audio is never persisted; only this aggregate summary is stored.
public struct AudioBreathMetrics: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let permissionGranted: Bool
    public let targetBreathingBPM: Double
    public let estimatedBreathingBPM: Double?
    public let adherenceScore: Double?  // 0...1, nil when timing is not measurable
    public let confidence: Double       // 0...1 conservative confidence in the estimate
    public let dataQuality: AudioBreathDataQuality
    public let analyzedDurationSeconds: Double
    public let sampleCount: Int
    public let detectedPeakCount: Int
    public let signalToNoiseRatio: Double?

    public init(
        enabled: Bool,
        permissionGranted: Bool,
        targetBreathingBPM: Double,
        estimatedBreathingBPM: Double? = nil,
        adherenceScore: Double? = nil,
        confidence: Double = 0,
        dataQuality: AudioBreathDataQuality = .unavailable,
        analyzedDurationSeconds: Double = 0,
        sampleCount: Int = 0,
        detectedPeakCount: Int = 0,
        signalToNoiseRatio: Double? = nil
    ) {
        self.enabled = enabled
        self.permissionGranted = permissionGranted
        self.targetBreathingBPM = targetBreathingBPM
        self.estimatedBreathingBPM = estimatedBreathingBPM
        self.adherenceScore = adherenceScore
        self.confidence = confidence
        self.dataQuality = dataQuality
        self.analyzedDurationSeconds = analyzedDurationSeconds
        self.sampleCount = sampleCount
        self.detectedPeakCount = detectedPeakCount
        self.signalToNoiseRatio = signalToNoiseRatio
    }
}

// MARK: - Breathing Session Record

/// On-Storj record for a completed breathing session.
/// Stored at: <userPrefix>/breathing/<sessionId>.json
public struct BreathingSessionRecord: Codable, Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let durationSeconds: Int
    public let bpm: Double
    public let ratio: String          // e.g. "1:1", "4:6"
    public let baselineHRV: Double?   // ms — nil for iPhone-only sessions
    public let recoveryHRV: Double?   // ms — nil for iPhone-only sessions
    public let avgHRV: Double?        // ms — nil for iPhone-only sessions
    public let coherenceScore: Double? // 0–1 — nil for iPhone-only sessions
    public let reflectionRating: Int? // 1–5, nil if skipped
    public let source: SessionSource  // .watch or .phone
    public let audioBreathMetrics: AudioBreathMetrics?

    public init(
        id: String = UUID().uuidString,
        timestamp: Date,
        durationSeconds: Int,
        bpm: Double,
        ratio: String,
        baselineHRV: Double? = nil,
        recoveryHRV: Double? = nil,
        avgHRV: Double? = nil,
        coherenceScore: Double? = nil,
        reflectionRating: Int? = nil,
        source: SessionSource = .watch,
        audioBreathMetrics: AudioBreathMetrics? = nil
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
        self.source           = source
        self.audioBreathMetrics = audioBreathMetrics
    }

    // Custom decoder for backward compatibility: legacy Watch records don't have `source`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try  c.decode(String.self,        forKey: .id)
        timestamp       = try  c.decode(Date.self,          forKey: .timestamp)
        durationSeconds = try  c.decode(Int.self,           forKey: .durationSeconds)
        bpm             = try  c.decode(Double.self,        forKey: .bpm)
        ratio           = try  c.decode(String.self,        forKey: .ratio)
        baselineHRV     = try  c.decodeIfPresent(Double.self, forKey: .baselineHRV)
        recoveryHRV     = try  c.decodeIfPresent(Double.self, forKey: .recoveryHRV)
        avgHRV          = try  c.decodeIfPresent(Double.self, forKey: .avgHRV)
        coherenceScore  = try  c.decodeIfPresent(Double.self, forKey: .coherenceScore)
        reflectionRating = try c.decodeIfPresent(Int.self,  forKey: .reflectionRating)
        source = (try c.decodeIfPresent(SessionSource.self, forKey: .source)) ?? .watch
        audioBreathMetrics = try c.decodeIfPresent(AudioBreathMetrics.self, forKey: .audioBreathMetrics)
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
        var data = [
            "sessionId":       record.id,
            "durationSeconds": String(record.durationSeconds),
            "bpm":             String(record.bpm),
            "ratio":           record.ratio,
            "source":          record.source.rawValue,
            "coherenceScore":  String(format: "%.3f", record.coherenceScore ?? 0),
            "avgHRV":          String(format: "%.1f", record.avgHRV ?? 0),
            "baselineHRV":     String(format: "%.1f", record.baselineHRV ?? 0),
            "recoveryHRV":     String(format: "%.1f", record.recoveryHRV ?? 0)
        ]
        if let audio = record.audioBreathMetrics {
            data["audioBreathTracking"] = String(audio.enabled)
            data["audioBreathQuality"] = audio.dataQuality.rawValue
            data["audioBreathConfidence"] = String(format: "%.2f", audio.confidence)
            if let estimated = audio.estimatedBreathingBPM {
                data["audioEstimatedBPM"] = String(format: "%.1f", estimated)
            }
            if let adherence = audio.adherenceScore {
                data["audioAdherenceScore"] = String(format: "%.2f", adherence)
            }
        }
        self.data = data
        self.metadata = Metadata(platform: platform, version: "1", source: "user")
    }
}

// MARK: - Coaching Insight

/// Bounded facts sent to the backend for post-session coaching.
/// This intentionally excludes raw audio and stores only aggregate metrics.
public struct CoachingSessionFacts: Codable, Equatable, Sendable {
    public let sessionId: String
    public let timestampISO8601: String
    public let durationSeconds: Int
    public let targetBreathingBPM: Double
    public let ratio: String
    public let source: SessionSource
    public let avgHRV: Double?
    public let coherenceScore: Double?
    public let reflectionRating: Int?
    public let audio: CoachingAudioFacts?

    public init(
        sessionId: String,
        timestampISO8601: String,
        durationSeconds: Int,
        targetBreathingBPM: Double,
        ratio: String,
        source: SessionSource,
        avgHRV: Double? = nil,
        coherenceScore: Double? = nil,
        reflectionRating: Int? = nil,
        audio: CoachingAudioFacts? = nil
    ) {
        self.sessionId = sessionId
        self.timestampISO8601 = timestampISO8601
        self.durationSeconds = durationSeconds
        self.targetBreathingBPM = targetBreathingBPM
        self.ratio = ratio
        self.source = source
        self.avgHRV = avgHRV
        self.coherenceScore = coherenceScore
        self.reflectionRating = reflectionRating
        self.audio = audio
    }

    public init(record: BreathingSessionRecord) {
        self.init(
            sessionId: record.id,
            timestampISO8601: ISO8601DateFormatter().string(from: record.timestamp),
            durationSeconds: record.durationSeconds,
            targetBreathingBPM: record.bpm,
            ratio: record.ratio,
            source: record.source,
            avgHRV: record.avgHRV,
            coherenceScore: record.coherenceScore,
            reflectionRating: record.reflectionRating,
            audio: record.audioBreathMetrics.map(CoachingAudioFacts.init(metrics:))
        )
    }
}

public struct CoachingAudioFacts: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let permissionGranted: Bool
    public let targetBreathingBPM: Double
    public let estimatedBreathingBPM: Double?
    public let adherenceScore: Double?
    public let confidence: Double
    public let dataQuality: AudioBreathDataQuality
    public let analyzedDurationSeconds: Double
    public let detectedPeakCount: Int
    public let signalToNoiseRatio: Double?

    public init(
        enabled: Bool,
        permissionGranted: Bool,
        targetBreathingBPM: Double,
        estimatedBreathingBPM: Double? = nil,
        adherenceScore: Double? = nil,
        confidence: Double,
        dataQuality: AudioBreathDataQuality,
        analyzedDurationSeconds: Double,
        detectedPeakCount: Int,
        signalToNoiseRatio: Double? = nil
    ) {
        self.enabled = enabled
        self.permissionGranted = permissionGranted
        self.targetBreathingBPM = targetBreathingBPM
        self.estimatedBreathingBPM = estimatedBreathingBPM
        self.adherenceScore = adherenceScore
        self.confidence = confidence
        self.dataQuality = dataQuality
        self.analyzedDurationSeconds = analyzedDurationSeconds
        self.detectedPeakCount = detectedPeakCount
        self.signalToNoiseRatio = signalToNoiseRatio
    }

    public init(metrics: AudioBreathMetrics) {
        self.init(
            enabled: metrics.enabled,
            permissionGranted: metrics.permissionGranted,
            targetBreathingBPM: metrics.targetBreathingBPM,
            estimatedBreathingBPM: metrics.estimatedBreathingBPM,
            adherenceScore: metrics.adherenceScore,
            confidence: metrics.confidence,
            dataQuality: metrics.dataQuality,
            analyzedDurationSeconds: metrics.analyzedDurationSeconds,
            detectedPeakCount: metrics.detectedPeakCount,
            signalToNoiseRatio: metrics.signalToNoiseRatio
        )
    }
}

public struct CoachingInsightRequest: Encodable, Sendable {
    public let message: String
    public let context: CoachingInsightContext
    public let history: [CoachingHistoryMessage]
    public let options: CoachingOptions

    /// First-turn coaching request (empty history).
    public init(facts: CoachingSessionFacts) {
        self.init(
            facts: facts,
            history: [],
            message: Self.initialPrompt(for: facts),
            options: CoachingOptions(mode: "quick")
        )
    }

    /// Multi-turn coaching request; `context` always includes bounded session facts.
    public init(
        facts: CoachingSessionFacts,
        history: [CoachingHistoryMessage],
        message: String,
        options: CoachingOptions = CoachingOptions(mode: "quick")
    ) {
        self.message = message
        self.context = CoachingInsightContext(facts: facts)
        self.history = history
        self.options = options
    }

    /// User-visible label stored in local thread history for the first turn.
    public static let initialUserDisplayMessage = "Summarize my session"

    static func initialPrompt(for facts: CoachingSessionFacts) -> String {
        var instructions = [
            "You are a supportive breathing coach reviewing one completed session.",
            "Summarize what went well, what stood out in the metrics, and up to two practical ideas for the next session.",
            "Use only the bounded session facts in context. Do not diagnose medical conditions.",
            "Do not claim to hear or analyze raw audio; microphone data is aggregate metrics only.",
            "If metrics are missing or weak, say so briefly and keep advice conservative."
        ]

        if facts.reflectionRating != nil {
            instructions.append("Reference the reflection rating (1–5) when interpreting how the session felt.")
        }
        if facts.coherenceScore != nil {
            instructions.append("Comment on coherence score (0–1) and what it suggests about breath–heart synchronization.")
        }
        if facts.avgHRV != nil {
            instructions.append("Reference average HRV (ms) when discussing autonomic balance during the session.")
        }
        instructions.append(
            "Target breathing pace was \(String(format: "%.1f", facts.targetBreathingBPM)) BPM at ratio \(facts.ratio)."
        )

        if let audio = facts.audio, audio.isReliableForCoaching {
            instructions.append(
                "Audio breath tracking quality is \(audio.dataQuality.rawValue): use estimated BPM, adherence (timing match), and confidence when interpreting breathing timing."
            )
            if audio.confidence < 0.5 {
                instructions.append("Audio confidence is low—note uncertainty before making strong timing claims.")
            }
        } else if facts.audio != nil {
            instructions.append(
                "Audio metrics are present but low quality or incomplete—mention limited microphone confidence if discussing breath timing."
            )
        }

        instructions.append("Return one short paragraph plus up to two bullet-style next-session suggestions.")
        return instructions.joined(separator: " ")
    }

    static func followUpSystemHint(for facts: CoachingSessionFacts) -> String {
        var hint = "Answer the user's follow-up question using the same bounded session facts in context. Stay concise and practical."
        if let audio = facts.audio, audio.isReliableForCoaching {
            hint += " Prefer audio estimated BPM and adherence when the question is about breathing timing."
        }
        hint += " Do not diagnose. Note low confidence when data is weak."
        return hint
    }
}

extension CoachingAudioFacts {
    /// Fair or good quality with permission — safe to reference timing metrics in coaching.
    public var isReliableForCoaching: Bool {
        enabled && permissionGranted && (dataQuality == .good || dataQuality == .fair)
    }
}

public struct CoachingInsightContext: Encodable, Sendable {
    public let contextBlocks: [CoachingContextBlock]
    public let source: String

    public init(facts: CoachingSessionFacts) {
        self.source = "AmachBreathe"
        self.contextBlocks = [
            CoachingContextBlock(
                type: "breathing_session_facts",
                content: Self.render(facts: facts)
            )
        ]
    }

    private static func render(facts: CoachingSessionFacts) -> String {
        var lines = [
            "Session ID: \(facts.sessionId)",
            "Timestamp: \(facts.timestampISO8601)",
            "Duration seconds: \(facts.durationSeconds)",
            "Target breathing BPM: \(format(facts.targetBreathingBPM))",
            "Ratio: \(facts.ratio)",
            "Source: \(facts.source.rawValue)"
        ]
        if let avgHRV = facts.avgHRV {
            lines.append("Average HRV ms: \(format(avgHRV))")
        }
        if let coherenceScore = facts.coherenceScore {
            lines.append("Coherence score 0-1: \(format(coherenceScore))")
        }
        if let reflectionRating = facts.reflectionRating {
            lines.append("Reflection rating 1-5: \(reflectionRating)")
        }
        if let audio = facts.audio {
            lines.append("Audio tracking enabled: \(audio.enabled)")
            lines.append("Audio permission granted: \(audio.permissionGranted)")
            lines.append("Audio data quality: \(audio.dataQuality.rawValue)")
            lines.append("Audio confidence 0-1: \(format(audio.confidence))")
            lines.append("Audio analyzed seconds: \(format(audio.analyzedDurationSeconds))")
            lines.append("Audio detected peak count: \(audio.detectedPeakCount)")
            if let estimated = audio.estimatedBreathingBPM {
                lines.append("Audio estimated BPM: \(format(estimated))")
            }
            if let adherence = audio.adherenceScore {
                lines.append("Audio adherence score 0-1: \(format(adherence))")
            }
            if let signalToNoise = audio.signalToNoiseRatio {
                lines.append("Audio signal-to-noise ratio: \(format(signalToNoise))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

public struct CoachingContextBlock: Encodable, Sendable {
    public let type: String
    public let content: String
}

public struct CoachingHistoryMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    public static func user(_ content: String) -> CoachingHistoryMessage {
        CoachingHistoryMessage(role: "user", content: content)
    }

    public static func assistant(_ content: String) -> CoachingHistoryMessage {
        CoachingHistoryMessage(role: "assistant", content: content)
    }

    public var isUser: Bool { role == "user" }
    public var isAssistant: Bool { role == "assistant" }
}

/// Persisted per-session coach thread (local device only; not uploaded to Storj).
public struct SessionCoachingState: Codable, Equatable, Sendable {
    public var messages: [CoachingHistoryMessage]
    public var lastInsight: CoachingInsight?

    public init(
        messages: [CoachingHistoryMessage] = [],
        lastInsight: CoachingInsight? = nil
    ) {
        self.messages = messages
        self.lastInsight = lastInsight
    }
}

public struct CoachingOptions: Encodable, Sendable {
    public let mode: String

    public init(mode: String) {
        self.mode = mode
    }
}

public struct CoachingInsight: Codable, Equatable, Sendable {
    public let content: String
    public let suggestions: [String]
    public let model: String?

    public init(content: String, suggestions: [String] = [], model: String? = nil) {
        self.content = content
        self.suggestions = suggestions
        self.model = model
    }
}

public struct CoachingInsightResponse: Decodable, Sendable {
    public let content: String
    public let suggestions: [String]?
    public let model: String?

    public var insight: CoachingInsight {
        CoachingInsight(content: content, suggestions: suggestions ?? [], model: model)
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
