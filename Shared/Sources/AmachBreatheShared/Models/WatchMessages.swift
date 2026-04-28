import Foundation

// WCSession message keys and envelope types for Watch ↔ iPhone communication.

public enum WatchMessageKey: String, Sendable {
    case type
    case payload
}

public enum WatchMessageType: String, Codable, Sendable {
    case sessionComplete      // Watch → iPhone: BreathingSessionRecord JSON
    case calibrationResult    // Watch → iPhone: ResonanceFrequencyResult JSON
    case startSession         // iPhone → Watch: StartSessionCommand JSON
    case cancelSession        // iPhone → Watch: no payload
    case walletState          // iPhone → Watch: WalletStateMessage JSON
    case walletStateRequest   // Watch → iPhone: no payload (Watch requests current state)
}

public struct StartSessionCommand: Codable, Sendable {
    public let bpm: Double
    public let durationSeconds: Int  // 300, 600, or 900
    public let ratio: String?        // BreathRatio.rawValue; nil = use watch default

    public init(bpm: Double, durationSeconds: Int, ratio: String? = nil) {
        self.bpm = bpm
        self.durationSeconds = durationSeconds
        self.ratio = ratio
    }
}

public struct ResonanceFrequencyResult: Codable, Sendable {
    public let resonanceBPM: Double
    public let scores: [Double: Double]  // bpm → coherence score

    public init(resonanceBPM: Double, scores: [Double: Double]) {
        self.resonanceBPM = resonanceBPM
        self.scores = scores
    }
}

/// Wallet state pushed from iPhone → Watch so the Watch can show connected/disconnected UI.
public struct WalletStateMessage: Codable, Sendable {
    public let isConnected: Bool
    public let walletAddress: String?   // nil when disconnected

    public init(isConnected: Bool, walletAddress: String?) {
        self.isConnected = isConnected
        self.walletAddress = walletAddress
    }
}

/// Wraps any Codable payload into a [String: Any] WCSession message dict.
public func makeWatchMessage<T: Encodable>(type: WatchMessageType, payload: T) throws -> [String: Any] {
    let data = try JSONEncoder().encode(payload)
    let payloadString = String(decoding: data, as: UTF8.self)
    return [
        WatchMessageKey.type.rawValue: type.rawValue,
        WatchMessageKey.payload.rawValue: payloadString
    ]
}

/// Makes a no-payload message (for cancelSession, walletStateRequest, etc.).
public func makeWatchMessage(type: WatchMessageType) -> [String: Any] {
    [WatchMessageKey.type.rawValue: type.rawValue]
}

/// Decodes a payload from a WCSession message dict.
public func decodeWatchPayload<T: Decodable>(_ type: T.Type, from message: [String: Any]) throws -> T {
    guard let payloadString = message[WatchMessageKey.payload.rawValue] as? String,
          let data = payloadString.data(using: .utf8) else {
        throw WatchMessageError.missingPayload
    }
    return try JSONDecoder().decode(type, from: data)
}

public func watchMessageType(from message: [String: Any]) -> WatchMessageType? {
    guard let raw = message[WatchMessageKey.type.rawValue] as? String else { return nil }
    return WatchMessageType(rawValue: raw)
}

public enum WatchMessageError: Error, Sendable {
    case missingPayload
    case unknownType
}
