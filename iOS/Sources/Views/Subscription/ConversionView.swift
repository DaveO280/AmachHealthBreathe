import SwiftUI
import AmachBreatheShared

/// Trial-end conversion screen: two equal-weight cards ("Continue free" / "Subscribe").
/// Shown when trial ends without purchase. Dismisses when user makes a choice.
struct ConversionView: View {

    @EnvironmentObject private var subscriptionService: SubscriptionService
    @EnvironmentObject private var sessionService: SessionService

    var body: some View {
        ZStack {
            Color.amachBg.ignoresSafeArea()
            VStack(spacing: AmachSpacing.lg) {
                header
                    .padding(.top, AmachSpacing.xl)
                Spacer()
                HStack(spacing: AmachSpacing.md) {
                    freeCard
                    paidCard
                }
                .padding(.horizontal, AmachSpacing.screenEdge)
                footer
                    .padding(.bottom, AmachSpacing.xl)
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: AmachSpacing.sm) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.amachPrimary)
            Text("Your trial has ended")
                .font(AmachType.h1)
                .foregroundStyle(Color.amachTextPrimary)
            Text("Choose how you'd like to continue")
                .font(AmachType.caption)
                .foregroundStyle(Color.amachTextSecondary)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Free card

    private var freeCard: some View {
        conversionCard(
            icon: "checkmark.shield",
            iconColor: Color.amachPrimary,
            title: "Continue with Amach",
            subtitle: "Free",
            features: [
                "Keep your session history",
                "Sync 3+ sessions/month",
                "Stay connected to the protocol"
            ],
            ctaLabel: "Continue Free",
            ctaStyle: .outline
        ) {
            subscriptionService.dismissConversionScreen()
        }
    }

    // MARK: - Paid card

    private var paidCard: some View {
        conversionCard(
            icon: "star.circle.fill",
            iconColor: Color(hex: "F59E0B"),
            title: "Subscribe",
            subtitle: "$4.99/month",
            features: [
                "Unlimited sessions",
                "No activity requirement",
                "Support the protocol"
            ],
            ctaLabel: "Subscribe",
            ctaStyle: .filled
        ) {
            Task { await subscriptionService.purchase() }
        }
    }

    // MARK: - Card builder

    private enum CTAStyle { case outline, filled }

    private func conversionCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        features: [String],
        ctaLabel: String,
        ctaStyle: CTAStyle,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: AmachSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(iconColor)
            VStack(spacing: 4) {
                Text(title)
                    .font(AmachType.h3)
                    .foregroundStyle(Color.amachTextPrimary)
                Text(subtitle)
                    .font(AmachType.caption)
                    .foregroundStyle(iconColor)
                    .fontWeight(.semibold)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.amachPrimary)
                        Text(feature)
                            .font(AmachType.tiny)
                            .foregroundStyle(Color.amachTextSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            Button(action: action) {
                if subscriptionService.isLoading && ctaStyle == .filled {
                    ProgressView().tint(ctaStyle == .filled ? .white : Color.amachPrimary)
                } else {
                    Text(ctaLabel)
                        .font(AmachType.caption.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(ctaStyle == .filled ? Color.amachPrimary : Color.clear)
            .foregroundStyle(ctaStyle == .filled ? .white : Color.amachPrimary)
            .overlay(
                RoundedRectangle(cornerRadius: AmachRadius.md)
                    .strokeBorder(Color.amachPrimary, lineWidth: ctaStyle == .outline ? 1.5 : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
            .disabled(subscriptionService.isLoading)
        }
        .padding(AmachSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 4) {
            if let err = subscriptionService.purchaseError {
                Text(err).font(AmachType.tiny).foregroundStyle(Color.amachDestructive)
            }
            Text("Subscription auto-renews monthly. Cancel any time in Settings.")
                .font(AmachType.tiny)
                .foregroundStyle(Color.amachTextTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AmachSpacing.lg)
        }
    }
}
