import SwiftUI
import AmachBreatheShared

struct SubscriptionManagementView: View {

    @EnvironmentObject private var subscriptionService: SubscriptionService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.amachBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: AmachSpacing.sectionSpacing) {
                        statusCard
                        actionsSection
                        legalSection
                    }
                    .padding(AmachSpacing.screenEdge)
                    .padding(.bottom, AmachSpacing.xxl)
                }
            }
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.amachPrimary)
                }
            }
            .sheet(isPresented: $subscriptionService.showCancelSubscriptionPrompt) {
                CancelSubscriptionSheet()
                    .environmentObject(subscriptionService)
                    .presentationDetents([.height(320)])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Status card

    private var statusCard: some View {
        VStack(spacing: AmachSpacing.sm) {
            Image(systemName: statusIcon)
                .font(.system(size: AmachType.iconCard))
                .foregroundStyle(statusColor)
            Text(statusTitle)
                .font(AmachType.h2)
                .foregroundStyle(Color.amachTextPrimary)
            Text(statusSubtitle)
                .font(AmachType.caption)
                .foregroundStyle(Color.amachTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(AmachSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.card))
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 0) {
            switch subscriptionService.state {
            case .trial, .expired:
                actionRow(label: "Subscribe — $4.99/month", icon: "star.circle.fill", accent: true) {
                    Task { await subscriptionService.purchase() }
                }
                Divider().padding(.leading, AmachSpacing.md)
                actionRow(label: "Restore Purchases", icon: "arrow.clockwise") {
                    Task { await subscriptionService.restorePurchases() }
                }
            case .subscribed:
                actionRow(label: "Manage in App Store", icon: "arrow.up.right.square") {
                    openSubscriptionSettings()
                }
                Divider().padding(.leading, AmachSpacing.md)
                actionRow(label: "Use Free Plan", icon: "checkmark.shield", destructive: true) {
                    subscriptionService.requestCancelSubscription()
                }
            case .connected:
                actionRow(label: "Subscribe — $4.99/month", icon: "star.circle.fill", accent: true) {
                    Task { await subscriptionService.purchase() }
                }
                Divider().padding(.leading, AmachSpacing.md)
                actionRow(label: "Restore Purchases", icon: "arrow.clockwise") {
                    Task { await subscriptionService.restorePurchases() }
                }
            }
        }
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
        .overlay {
            if subscriptionService.isLoading {
                RoundedRectangle(cornerRadius: AmachRadius.md)
                    .fill(Color.amachSurface.opacity(0.7))
                ProgressView()
            }
        }
    }

    private func actionRow(
        label: String,
        icon: String,
        accent: Bool = false,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AmachSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(destructive ? Color.amachDestructive : accent ? Color.amachPrimary : Color.amachTextSecondary)
                    .frame(width: 24)
                Text(label)
                    .font(AmachType.body)
                    .foregroundStyle(destructive ? Color.amachDestructive : Color.amachTextPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.amachTextTertiary)
            }
            .padding(AmachSpacing.md)
        }
        .disabled(subscriptionService.isLoading)
    }

    // MARK: - Legal / error footer

    private var legalSection: some View {
        VStack(spacing: AmachSpacing.xs) {
            if let err = subscriptionService.purchaseError {
                Text(err)
                    .font(AmachType.tiny)
                    .foregroundStyle(Color.amachDestructive)
                    .multilineTextAlignment(.center)
            }
            Text("Subscription auto-renews monthly at $4.99. Cancel any time in App Store Settings.")
                .font(AmachType.tiny)
                .foregroundStyle(Color.amachTextTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, AmachSpacing.lg)
    }

    // MARK: - Computed state display

    private var statusIcon: String {
        switch subscriptionService.state {
        case .trial:      return "clock"
        case .subscribed: return "star.circle.fill"
        case .connected:  return "checkmark.shield.fill"
        case .expired:    return "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch subscriptionService.state {
        case .trial:      return Color.amachPrimary
        case .subscribed: return Color.amachGold
        case .connected:  return Color.amachPrimary
        case .expired:    return Color.amachDestructive
        }
    }

    private var statusTitle: String {
        switch subscriptionService.state {
        case .trial:      return "Free Trial"
        case .subscribed: return "Subscribed"
        case .connected:  return "Connected — Free"
        case .expired:    return "Trial Ended"
        }
    }

    private var statusSubtitle: String {
        switch subscriptionService.state {
        case .trial:      return "7-day trial. Sync sessions to stay free, or subscribe."
        case .subscribed: return "Unlimited sessions. Thank you for supporting Amach."
        case .connected:  return "Sync 3+ sessions per month to keep access."
        case .expired:    return "Subscribe or sync 3 sessions to regain access."
        }
    }

    // MARK: - Helpers

    private func openSubscriptionSettings() {
        if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
    }
}
