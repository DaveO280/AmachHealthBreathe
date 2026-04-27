import Foundation

// MARK: - Subscription state record (stored in Storj for cross-device sync)

public struct SubscriptionRecord: Codable, Sendable {
    public let walletAddress: String
    public let state: SubscriptionState
    public let updatedAt: Date
    public let transactionId: String?    // StoreKit transaction ID for subscribed state
    public let connectedSince: Date?     // when user first achieved connected tier

    public init(
        walletAddress: String,
        state: SubscriptionState,
        updatedAt: Date = Date(),
        transactionId: String? = nil,
        connectedSince: Date? = nil
    ) {
        self.walletAddress = walletAddress
        self.state = state
        self.updatedAt = updatedAt
        self.transactionId = transactionId
        self.connectedSince = connectedSince
    }
}

// MARK: - Cost telemetry (posted to /api/tracking for analytics)

public struct SubscriptionTelemetryEvent: Encodable, Sendable {
    public let eventType: String        // "subscription_state_change" | "cost_telemetry" | "mau"
    public let walletAddress: String
    public let subscriptionState: String
    public let platform: String         // "ios"
    public let appVersion: String
    public let timestamp: Date
    /// Optional metrics payload for cost_telemetry events
    public let metrics: CostMetrics?

    public init(
        eventType: String,
        walletAddress: String,
        subscriptionState: SubscriptionState,
        platform: String = "ios",
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
        timestamp: Date = Date(),
        metrics: CostMetrics? = nil
    ) {
        self.eventType = eventType
        self.walletAddress = walletAddress
        self.subscriptionState = subscriptionState.rawValue
        self.platform = platform
        self.appVersion = appVersion
        self.timestamp = timestamp
        self.metrics = metrics
    }
}

/// Cost-breakdown metrics for telemetry. All fields are optional — send what's known.
public struct CostMetrics: Encodable, Sendable {
    public let sessionCount30Days: Int?       // uploaded sessions in rolling 30d
    public let storjUploadCount: Int?         // total Storj objects for this user
    public let revenueUSD: Double?            // subscription revenue this period (0 for connected/trial)
    public let previousState: String?         // state before transition

    public init(
        sessionCount30Days: Int? = nil,
        storjUploadCount: Int? = nil,
        revenueUSD: Double? = nil,
        previousState: SubscriptionState? = nil
    ) {
        self.sessionCount30Days = sessionCount30Days
        self.storjUploadCount = storjUploadCount
        self.revenueUSD = revenueUSD
        self.previousState = previousState?.rawValue
    }
}

// MARK: - StoreKit product IDs

public enum SubscriptionProduct {
    public static let monthly = "com.amach.breathe.monthly"
    public static let allIDs: Set<String> = [monthly]
    public static let monthlyPriceUSD: Double = 4.99
}
