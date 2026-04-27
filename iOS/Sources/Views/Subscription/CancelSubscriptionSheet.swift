import SwiftUI
import AmachBreatheShared

/// Sheet confirming that the user wants to stop auto-renewal and drop to the free plan.
struct CancelSubscriptionSheet: View {

    @EnvironmentObject private var subscriptionService: SubscriptionService

    var body: some View {
        VStack(spacing: AmachSpacing.lg) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: AmachType.iconAlert))
                .foregroundStyle(Color.amachPrimary)
                .padding(.top, AmachSpacing.md)

            VStack(spacing: AmachSpacing.xs) {
                Text("Switch to Free Plan?")
                    .font(AmachType.h2)
                    .foregroundStyle(Color.amachTextPrimary)
                Text("You'll keep access as long as you sync 3+ sessions per month. Cancel auto-renewal in App Store Settings.")
                    .font(AmachType.caption)
                    .foregroundStyle(Color.amachTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AmachSpacing.lg)
            }

            VStack(spacing: AmachSpacing.sm) {
                Button {
                    openSubscriptionSettings()
                } label: {
                    Text("Cancel in App Store")
                        .font(AmachType.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.amachDestructive)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
                }

                Button {
                    subscriptionService.dismissCancelPrompt()
                } label: {
                    Text("Keep Subscription")
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

    private func openSubscriptionSettings() {
        if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
        subscriptionService.dismissCancelPrompt()
    }
}
