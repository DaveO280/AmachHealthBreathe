import SwiftUI
import AmachBreatheShared

/// Bottom sheet shown when a connected user's activity lapses below the threshold.
struct SyncOrSubscribeSheet: View {

    @EnvironmentObject private var subscriptionService: SubscriptionService

    var body: some View {
        VStack(spacing: AmachSpacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: AmachType.iconAlert))
                .foregroundStyle(Color.amachWarning)
                .padding(.top, AmachSpacing.md)

            VStack(spacing: AmachSpacing.xs) {
                Text("Stay Connected")
                    .font(AmachType.h2)
                    .foregroundStyle(Color.amachTextPrimary)
                Text("You need 3 sessions synced in the last 30 days to keep free access. Sync more sessions, or subscribe to continue without limits.")
                    .font(AmachType.caption)
                    .foregroundStyle(Color.amachTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AmachSpacing.lg)
            }

            VStack(spacing: AmachSpacing.sm) {
                Button {
                    Task { await subscriptionService.purchase() }
                } label: {
                    Group {
                        if subscriptionService.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Subscribe — $4.99/month")
                                .font(AmachType.caption.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.amachPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
                }
                .disabled(subscriptionService.isLoading)

                Button {
                    subscriptionService.dismissSyncOrSubscribePrompt()
                } label: {
                    Text("I'll Sync More Sessions")
                        .font(AmachType.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: AmachRadius.md)
                                .strokeBorder(Color.amachPrimary, lineWidth: 1.5)
                        )
                        .foregroundStyle(Color.amachPrimary)
                }
            }
            .padding(.horizontal, AmachSpacing.screenEdge)
            .padding(.bottom, AmachSpacing.lg)
        }
        .background(Color.amachBg)
    }
}
