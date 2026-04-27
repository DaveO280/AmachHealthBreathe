import Foundation
import StoreKit
import AmachBreatheShared

/// Manages subscription state via StoreKit 2.
/// State transitions are deliberate — call checkAndUpdateState() to evaluate.
/// No auto-transitions: the caller decides when to reassess.
@MainActor
public final class SubscriptionService: ObservableObject {

    // MARK: - Published state

    @Published public private(set) var state: SubscriptionState = .trial
    @Published public private(set) var isLoading = false
    @Published public private(set) var purchaseError: String?
    @Published public private(set) var availableProduct: Product?
    @Published public var showSoftSupportPrompt = false

    // MARK: - Prompt flags (public var — SwiftUI bindings need write access to dismiss)
    @Published public var showCancelSubscriptionPrompt = false
    @Published public var showSyncOrSubscribePrompt = false
    @Published public var showConversionScreen = false

    // MARK: - Config

    private let installDateKey       = "com.amach.breathe.installDate"
    private let stateKey             = "com.amach.breathe.subscriptionState"
    private let connectedSinceKey    = "com.amach.breathe.connectedSince"
    private let softPromptShownKey   = "com.amach.breathe.softPromptShown"
    private let transactionIdKey     = "com.amach.breathe.lastTransactionId"

    // MARK: - Dependencies

    private weak var sessionService: SessionService?
    private weak var walletService: WalletService?
    private var apiClient = AmachAPIClient()
    private var transactionObserverTask: Task<Void, Never>?

    // MARK: - Init

    public init(sessionService: SessionService? = nil, walletService: WalletService? = nil) {
        self.sessionService = sessionService
        self.walletService = walletService
        recordInstallDate()
        loadPersistedState()
    }

    // MARK: - Setup

    public func start() {
        Task {
            await loadProducts()
            await verifyCurrentEntitlements()
        }
        observeTransactionUpdates()
    }

    // MARK: - Products

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: SubscriptionProduct.allIDs)
            availableProduct = products.first
        } catch {
            // Products unavailable (simulator without StoreKit config) — non-fatal
        }
    }

    // MARK: - Purchase

    public func purchase() async {
        guard let product = availableProduct else { return }
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await applyEvent(.purchased, transactionId: String(transaction.id))
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Restore

    public func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await verifyCurrentEntitlements()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Entitlement verification

    public func verifyCurrentEntitlements() async {
        var hasActiveSubscription = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == SubscriptionProduct.monthly,
                  transaction.revocationDate == nil
            else { continue }
            if let expiryDate = transaction.expirationDate, Date() < expiryDate {
                hasActiveSubscription = true
                persistTransactionId(String(transaction.id))
            }
        }
        if hasActiveSubscription {
            await applyEvent(.restored)
        } else if state == .subscribed {
            await applyEvent(.subscriptionExpired)
        }
    }

    // MARK: - State evaluation

    /// Evaluate current conditions and fire events if thresholds are crossed.
    /// Call this on app foreground, after session sync, and after wallet connect.
    public func checkAndUpdateState(now: Date = Date()) async {
        let calendar = Calendar.current
        let uploadedTimestamps = uploadedSessionTimestamps()

        switch state {
        case .trial:
            if SubscriptionStateMachine.isActivelyConnected(
                uploadedTimestamps: uploadedTimestamps, from: now, calendar: calendar) {
                await applyEvent(.activeConnectionAchieved)
            } else if trialHasEnded(now: now) {
                await applyEvent(.trialEnded)
                showConversionScreen = true
            }

        case .subscribed:
            await verifyCurrentEntitlements()

        case .connected:
            if !SubscriptionStateMachine.isActivelyConnected(
                uploadedTimestamps: uploadedTimestamps, from: now, calendar: calendar) {
                await applyEvent(.connectionLapsed)
                showSyncOrSubscribePrompt = true
            } else {
                checkSoftSupportPrompt(now: now, calendar: calendar)
            }

        case .expired:
            if SubscriptionStateMachine.isActivelyConnected(
                uploadedTimestamps: uploadedTimestamps, from: now, calendar: calendar) {
                await applyEvent(.activeConnectionAchieved)
            }
        }
    }

    // MARK: - Cancel subscription prompt

    /// Called when a subscribed user taps "Use Free Plan".
    public func requestCancelSubscription() {
        guard state == .subscribed else { return }
        showCancelSubscriptionPrompt = true
    }

    /// User confirmed cancellation (stops auto-renewal via App Store).
    /// Sets state to connected if actively connected, otherwise expired.
    public func confirmCancelSubscription(now: Date = Date()) async {
        showCancelSubscriptionPrompt = false
        let uploadedTimestamps = uploadedSessionTimestamps()
        let isActive = SubscriptionStateMachine.isActivelyConnected(
            uploadedTimestamps: uploadedTimestamps, from: now)
        await applyEvent(.userRequestedCancel)
        if !isActive { await applyEvent(.connectionLapsed) }
    }

    public func dismissCancelPrompt() { showCancelSubscriptionPrompt = false }
    public func dismissSyncOrSubscribePrompt() { showSyncOrSubscribePrompt = false }
    public func dismissConversionScreen() { showConversionScreen = false }

    public func acknowledgeSoftSupportPrompt() {
        showSoftSupportPrompt = false
        UserDefaults.standard.set(true, forKey: softPromptShownKey)
    }

    // MARK: - Telemetry

    public func sendStateTelemetry(previousState: SubscriptionState? = nil) {
        guard let wallet = walletService, wallet.isConnected,
              let key = wallet.encryptionKey else { return }
        let sessions = sessionService?.sessions ?? []
        let uploaded = sessions.filter { $0.uploadStatus == .uploaded }
        let metrics = CostMetrics(
            sessionCount30Days: SubscriptionStateMachine.activeSessionCount(
                uploadedTimestamps: uploadedSessionTimestamps(),
                from: Date()),
            storjUploadCount: uploaded.count,
            revenueUSD: state == .subscribed ? SubscriptionProduct.monthlyPriceUSD : 0,
            previousState: previousState
        )
        let event = SubscriptionTelemetryEvent(
            eventType: previousState != nil ? "subscription_state_change" : "subscription_check",
            walletAddress: wallet.address ?? "",
            subscriptionState: state,
            metrics: metrics
        )
        Task {
            try? await apiClient.submitTelemetry(event, encryptionKey: key)
        }
    }

    // MARK: - Transaction observer

    private func observeTransactionUpdates() {
        transactionObserverTask?.cancel()
        transactionObserverTask = Task(priority: .background) {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result,
                      transaction.productID == SubscriptionProduct.monthly else { continue }
                await transaction.finish()
                if transaction.revocationDate != nil {
                    await applyEvent(.subscriptionExpired)
                } else {
                    await applyEvent(.purchased, transactionId: String(transaction.id))
                }
            }
        }
    }

    // MARK: - Private helpers

    @discardableResult
    private func applyEvent(_ event: SubscriptionEvent, transactionId: String? = nil) async -> SubscriptionState {
        let previous = state
        let next = SubscriptionStateMachine.transition(from: state, event: event)
        guard next != previous else { return state }

        state = next
        persistState(next)

        if let tid = transactionId { persistTransactionId(tid) }
        if next == .connected, connectedSince == nil { persistConnectedSince(Date()) }

        sendStateTelemetry(previousState: previous)
        return next
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw SubscriptionError.unverifiedTransaction
        case .verified(let value): return value
        }
    }

    private func uploadedSessionTimestamps() -> [Date] {
        (sessionService?.sessions ?? [])
            .filter { $0.uploadStatus == .uploaded }
            .map { $0.breathingSession.timestamp }
    }

    private func trialHasEnded(now: Date) -> Bool {
        guard let installDate else { return false }
        return SubscriptionStateMachine.trialHasEnded(installDate: installDate, from: now)
    }

    private func checkSoftSupportPrompt(now: Date, calendar: Calendar) {
        guard let since = connectedSince else { return }
        let hasShown = UserDefaults.standard.bool(forKey: softPromptShownKey)
        if SubscriptionStateMachine.shouldShowSoftPrompt(
            connectedSince: since, from: now, hasShownBefore: hasShown, calendar: calendar) {
            showSoftSupportPrompt = true
        }
    }

    // MARK: - Persistence

    private var installDate: Date? { UserDefaults.standard.object(forKey: installDateKey) as? Date }
    private var connectedSince: Date? { UserDefaults.standard.object(forKey: connectedSinceKey) as? Date }

    private func recordInstallDate() {
        guard UserDefaults.standard.object(forKey: installDateKey) == nil else { return }
        UserDefaults.standard.set(Date(), forKey: installDateKey)
    }

    private func loadPersistedState() {
        guard let raw = UserDefaults.standard.string(forKey: stateKey),
              let s = SubscriptionState(rawValue: raw) else { return }
        state = s
    }

    private func persistState(_ s: SubscriptionState) {
        UserDefaults.standard.set(s.rawValue, forKey: stateKey)
    }

    private func persistTransactionId(_ id: String) {
        UserDefaults.standard.set(id, forKey: transactionIdKey)
    }

    private func persistConnectedSince(_ date: Date) {
        UserDefaults.standard.set(date, forKey: connectedSinceKey)
    }
}

// MARK: - Errors

public enum SubscriptionError: LocalizedError {
    case unverifiedTransaction

    public var errorDescription: String? {
        switch self {
        case .unverifiedTransaction: return "Transaction could not be verified with Apple"
        }
    }
}
