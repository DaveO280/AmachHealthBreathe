import SwiftUI
import AmachBreatheShared

/// One-time prompt shown to long-term connected users (~90 days) asking them to consider subscribing.
/// Dismissed and never shown again after the user acknowledges it.
struct SoftSupportPromptView: View {

    @EnvironmentObject private var subscriptionService: SubscriptionService

    var body: some View {
        VStack(spacing: AmachSpacing.lg) {
            Image(systemName: "heart.fill")
                .font(.system(size: AmachType.iconCard))
                .foregroundStyle(Color.amachDestructive)
                .padding(.top, AmachSpacing.md)

            VStack(spacing: AmachSpacing.xs) {
                Text("Enjoying Amach Breathe?")
                    .font(AmachType.h2)
                    .foregroundStyle(Color.amachPrimaryWordmark)
                    .amachShimmer(delay: 0.4)
                Text("You've been using Amach for 3 months on the free plan — thank you for staying with us. If you'd like to support ongoing development, subscribing for $4.99/month keeps the servers running.")
                    .font(AmachType.caption)
                    .foregroundStyle(Color.amachTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AmachSpacing.lg)
            }

            VStack(spacing: AmachSpacing.sm) {
                Button {
                    Task { await subscriptionService.purchase() }
                    subscriptionService.acknowledgeSoftSupportPrompt()
                } label: {
                    Group {
                        if subscriptionService.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Support with $4.99/month")
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
                    subscriptionService.acknowledgeSoftSupportPrompt()
                } label: {
                    Text("Maybe Later")
                        .font(AmachType.caption)
                        .foregroundStyle(Color.amachTextSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }
            .padding(.horizontal, AmachSpacing.screenEdge)
            .padding(.bottom, AmachSpacing.lg)
        }
        .background(Color.amachBg)
    }
}
