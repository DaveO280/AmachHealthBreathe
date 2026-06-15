import SwiftUI

// MARK: - BrandMarkLayout

public enum BrandMarkLayout {
    case icon
    case compact
    case stacked
}

// MARK: - AmachBrandMark
//
// The standalone brand wordmark — sits at the top of screens as a header.
// NEVER applied inline to body text. Three layouts, mirroring the
// AmachBrandMark in AmachHealth-iOS so the family looks identical:
//
//   .stacked  — onboarding hero (large icon above 2-line wordmark)
//   .compact  — top-of-screen header (small icon beside 2-line wordmark)
//   .icon     — icon-only (tab bar / chip use)
//
public struct AmachBrandMark: View {

    public var layout: BrandMarkLayout = .stacked
    public var iconSize: CGFloat?

    public init(layout: BrandMarkLayout = .stacked, iconSize: CGFloat? = nil) {
        self.layout = layout
        self.iconSize = iconSize
    }

    private var resolvedIconSize: CGFloat {
        if let s = iconSize { return s }
        switch layout {
        case .icon:    return 48
        case .compact: return 28
        case .stacked: return 68
        }
    }

    public var body: some View {
        switch layout {

        case .icon:
            BreatheGlyph(size: resolvedIconSize)

        case .compact:
            HStack(spacing: 9) {
                BreatheGlyph(size: resolvedIconSize, showRing: false)

                VStack(alignment: .leading, spacing: 1) {
                    Text("AMACH")
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .kerning(3)
                        .foregroundStyle(Color.amachPrimaryWordmark)
                        .amachShimmer(duration: 4.5, delay: 1.2)

                    Text("BREATHE")
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .kerning(3)
                        .foregroundStyle(Color.amachPrimaryWordmark.opacity(0.7))
                }
            }

        case .stacked:
            VStack(spacing: 14) {
                BreatheGlyph(size: resolvedIconSize)

                VStack(spacing: 5) {
                    Text("AMACH")
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .kerning(6)
                        .foregroundStyle(Color.amachPrimaryWordmark)
                        .amachShimmer(duration: 3.2, delay: 0.8)

                    Text("BREATHE")
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .kerning(7)
                        .foregroundStyle(Color.amachPrimaryWordmark)
                        .amachShimmer(duration: 3.2, delay: 1.4)

                    Text("Driven by data · Guided by Nature")
                        .font(.system(size: 11, weight: .light))
                        .italic()
                        .foregroundStyle(Color.amachTextSecondary.opacity(0.6))
                        .padding(.top, 2)
                }
            }
        }
    }
}

// MARK: - BreatheGlyph
//
// Stand-in icon for the Breathe brand mark. Concentric breathing rings
// in the same emerald palette as the reference Triskelion. Subtle pulse
// animation keeps the brand mark feeling alive without distracting.
//
public struct BreatheGlyph: View {

    public var size: CGFloat = 48
    public var showRing: Bool = true

    @State private var pulse: CGFloat = 0.92

    public init(size: CGFloat = 48, showRing: Bool = true) {
        self.size = size
        self.showRing = showRing
    }

    public var body: some View {
        ZStack {
            if showRing {
                Circle()
                    .stroke(Color.amachPrimary.opacity(0.18), lineWidth: max(1, size * 0.04))
                    .frame(width: size, height: size)
            }

            // Mid ring — animates breathing
            Circle()
                .stroke(Color.amachPrimary.opacity(0.55), lineWidth: max(1, size * 0.06))
                .frame(width: size * 0.72, height: size * 0.72)
                .scaleEffect(pulse)

            // Inner glow disc
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.amachPrimaryBright.opacity(0.85),
                            Color.amachPrimary.opacity(0.20)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.32
                    )
                )
                .frame(width: size * 0.42, height: size * 0.42)
                .shadow(color: Color.amachPrimary.opacity(0.45), radius: size * 0.10)
                .scaleEffect(pulse)
        }
        .frame(width: size, height: size)
        .onAppear {
            #if !os(macOS)
            withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
                pulse = 1.06
            }
            #endif
        }
    }
}

// MARK: - AmachNavigationHeader
//
// Replaces the default `.navigationTitle` chrome with an inline header that
// matches AmachHealth-iOS exactly: chevron back, title + optional subtitle,
// trailing slot for actions. Caller hides the system nav bar via
// `.toolbar(.hidden, for: .navigationBar)` when adopting this header.
//
#if os(iOS)
public struct AmachNavigationHeader<Trailing: View>: View {

    public let title: String
    public var subtitle: String?
    public var showBack: Bool = true
    public var backAction: (() -> Void)?
    @ViewBuilder public var trailing: () -> Trailing

    @Environment(\.dismiss) private var dismiss

    public init(
        title: String,
        subtitle: String? = nil,
        showBack: Bool = true,
        backAction: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showBack = showBack
        self.backAction = backAction
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: AmachSpacing.sm) {
            if showBack {
                Button {
                    AmachHaptics.cardTap()
                    if let custom = backAction { custom() } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.amachPrimary)
                        .frame(
                            width: AmachAccessibility.minTouchTarget,
                            height: AmachAccessibility.minTouchTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AmachType.h2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.amachTextPrimary)
                    .tracking(-0.2)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(AmachType.tiny)
                        .foregroundStyle(Color.amachTextSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()
            trailing()
        }
        .padding(.horizontal, AmachSpacing.md)
        .padding(.vertical, AmachSpacing.sm)
        .frame(minHeight: 52)
    }
}
#endif

// MARK: - AmachEmptyState
//
// Concentric-circle empty state matching AmachHealth-iOS: tinted glow halo,
// SF Symbol, title + body, optional CTA button. Replaces ad-hoc empty
// states scattered across History/Trends/etc.
//
public struct AmachEmptyState: View {

    public let icon: String
    public let title: String
    public let message: String
    public var tintColor: Color = Color.amachPrimary
    public var ctaLabel: String?
    public var ctaAction: (() -> Void)?

    public init(
        icon: String,
        title: String,
        message: String,
        tintColor: Color = Color.amachPrimary,
        ctaLabel: String? = nil,
        ctaAction: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.tintColor = tintColor
        self.ctaLabel = ctaLabel
        self.ctaAction = ctaAction
    }

    public var body: some View {
        VStack(spacing: AmachSpacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(tintColor.opacity(0.04))
                    .frame(width: 160, height: 160)
                Circle()
                    .fill(tintColor.opacity(0.07))
                    .frame(width: 128, height: 128)
                Image(systemName: icon)
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(tintColor.opacity(0.60))
                    .shadow(color: tintColor.opacity(0.22), radius: 20)
            }

            VStack(spacing: AmachSpacing.sm) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.amachTextPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(AmachType.body)
                    .foregroundStyle(Color.amachTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AmachSpacing.md)
            }

            #if os(iOS)
            if let ctaLabel, let ctaAction {
                Button(ctaLabel, action: ctaAction)
                    .amachPrimaryButtonStyle()
                    .padding(.horizontal, AmachSpacing.lg)
            }
            #endif

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
