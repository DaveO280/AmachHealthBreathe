// AmachDesignSystem.swift
// AmachBreatheShared — lifted from AmachHealth-iOS, adapted for iOS + watchOS
//
// Single source of truth for all design tokens.
// UIKit-dependent APIs are gated behind #if os(iOS).

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

// ============================================================
// MARK: - COLOR SYSTEM
// ============================================================

public extension Color {

    enum Amach {

        public static let primary      = Color(hex: "006B4F")
        public static let primaryDark  = Color(hex: "004D38")
        public static let p700         = Color(hex: "005941")
        public static let p500         = Color(hex: "008C66")
        public static let p400         = Color(hex: "10B981")
        public static let p300         = Color(hex: "34D399")
        public static let p200         = Color(hex: "6EE7B7")
        public static let p100         = Color(hex: "D1FAE5")
        public static let p50          = Color(hex: "ECFDF5")

        public static let accent = Color(hex: "F59E0B")
        public static let a600   = Color(hex: "D97706")
        public static let a100   = Color(hex: "FEF3C7")

        public enum AI {
            public static let base  = Color(hex: "6366F1")
            public static let light = Color(hex: "EEF2FF")
            public static let dark  = Color(hex: "3730A3")
            public static let p400  = Color(hex: "818CF8")
            public static let p200  = Color(hex: "C7D2FE")
        }

        public enum Semantic {
            public static let success        = Color(hex: "10B981")
            public static let successBgL     = Color(hex: "ECFDF5")
            public static let successBgD     = Color(hex: "064E3B")
            public static let successTextL   = Color(hex: "065F46")
            public static let successTextD   = Color(hex: "6EE7B7")
            public static let successBorder  = Color(hex: "6EE7B7")

            public static let warning        = Color(hex: "F59E0B")
            public static let warningBgL     = Color(hex: "FFFBEB")
            public static let warningBgD     = Color(hex: "78350F")
            public static let warningTextL   = Color(hex: "92400E")
            public static let warningTextD   = Color(hex: "FCD34D")
            public static let warningBorder  = Color(hex: "FCD34D")

            public static let error          = Color(hex: "EF4444")
            public static let errorBgL       = Color(hex: "FEF2F2")
            public static let errorBgD       = Color(hex: "7F1D1D")
            public static let errorTextL     = Color(hex: "991B1B")
            public static let errorTextD     = Color(hex: "FCA5A5")
            public static let errorBorder    = Color(hex: "FCA5A5")

            public static let info           = Color(hex: "3B82F6")
            public static let infoBgL        = Color(hex: "EFF6FF")
            public static let infoBgD        = Color(hex: "1E3A5F")
            public static let infoTextL      = Color(hex: "1D4ED8")
            public static let infoTextD      = Color(hex: "93C5FD")
            public static let infoBorder     = Color(hex: "93C5FD")
        }

        public enum Health {
            public static let optimal         = Color(hex: "059669")
            public static let optimalBgL      = Color(hex: "ECFDF5")
            public static let optimalBgD      = Color(hex: "064E3B")
            public static let optimalTextL    = Color(hex: "047857")
            public static let optimalTextD    = Color(hex: "34D399")

            public static let borderline      = Color(hex: "D97706")
            public static let borderlineBgL   = Color(hex: "FFFBEB")
            public static let borderlineBgD   = Color(hex: "451A03")
            public static let borderlineTextL = Color(hex: "92400E")
            public static let borderlineTextD = Color(hex: "FCD34D")

            public static let critical        = Color(hex: "DC2626")
            public static let criticalBgL     = Color(hex: "FEF2F2")
            public static let criticalBgD     = Color(hex: "450A0A")
            public static let criticalTextL   = Color(hex: "991B1B")
            public static let criticalTextD   = Color(hex: "FCA5A5")

            public static let noData          = Color(hex: "9CA3AF")
            public static let noDataBgL       = Color(hex: "F3F4F6")
            public static let noDataBgD       = Color(hex: "1F2937")
            public static let noDataTextL     = Color(hex: "6B7280")
            public static let noDataTextD     = Color(hex: "9CA3AF")
        }

        public enum Tier {
            public static let goldBg      = Color(hex: "FEF3C7")
            public static let goldText    = Color(hex: "B45309")
            public static let goldBorder  = Color(hex: "FCD34D")

            public static let silverBg     = Color(hex: "F1F5F9")
            public static let silverText   = Color(hex: "475569")
            public static let silverBorder = Color(hex: "CBD5E1")

            public static let bronzeBg     = Color(hex: "FDF0E6")
            public static let bronzeText   = Color(hex: "9A4B1C")
            public static let bronzeBorder = Color(hex: "E8A87C")

            public static let noneBg     = Color(hex: "F3F4F6")
            public static let noneText   = Color(hex: "6B7280")
            public static let noneBorder = Color(hex: "D1D5DB")
        }

        public enum Surface {
            public static let bgLight       = Color(hex: "FFFFFF")
            public static let surfaceLight  = Color(hex: "F9FAFB")
            public static let elevatedLight = Color(hex: "F3F4F6")

            public static let bgDark       = Color(hex: "0A1A15")
            public static let surfaceDark  = Color(hex: "111F1A")
            public static let elevatedDark = Color(hex: "1A2E26")
        }

        public enum Text {
            public static let primaryL   = Color(hex: "111827")
            public static let secondaryL = Color(hex: "6B7280")
            public static let tertiaryL  = Color(hex: "9CA3AF")

            public static let primaryD   = Color(hex: "F9FAFB")
            public static let secondaryD = Color(hex: "9CA3AF")
            public static let tertiaryD  = Color(hex: "6B7280")

            public static let onPrimary  = Color(hex: "FFFFFF")
            public static let onAccent   = Color(hex: "451A03")
            public static let onAI       = Color(hex: "FFFFFF")
        }
    }
}

public extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var n: UInt64 = 0
        Scanner(string: h).scanHexInt64(&n)
        let a, r, g, b: UInt64
        switch h.count {
        case 3:  (a,r,g,b) = (255,(n>>8)*17,(n>>4 & 0xF)*17,(n & 0xF)*17)
        case 6:  (a,r,g,b) = (255,n>>16,n>>8 & 0xFF,n & 0xFF)
        case 8:  (a,r,g,b) = (n>>24,n>>16 & 0xFF,n>>8 & 0xFF,n & 0xFF)
        default: (a,r,g,b) = (255,0,0,0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255,
                  blue: Double(b)/255, opacity: Double(a)/255)
    }
}


// ============================================================
// MARK: - ADAPTIVE COLOR API
// ============================================================

public extension Color {

#if os(iOS)
    static var amachBg: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(Amach.Surface.bgDark)
                : UIColor(Amach.Surface.bgLight)
        })
    }

    static var amachSurface: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(Amach.Surface.surfaceDark)
                : UIColor(Amach.Surface.surfaceLight)
        })
    }

    static var amachElevated: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(Amach.Surface.elevatedDark)
                : UIColor(Amach.Surface.elevatedLight)
        })
    }

    static var amachPrimary: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(Amach.p400)
                : UIColor(Amach.primary)
        })
    }

    static var amachAccent: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(Amach.accent)
                : UIColor(Amach.a600)
        })
    }

    static var amachTextPrimary: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(Amach.Text.primaryD)
                : UIColor(Amach.Text.primaryL)
        })
    }

    static var amachTextSecondary: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(Amach.Text.secondaryD)
                : UIColor(Amach.Text.secondaryL)
        })
    }

    static var amachTextTertiary: Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(Amach.Text.tertiaryD)
                : UIColor(Amach.Text.tertiaryL)
        })
    }

#else
    static var amachBg: Color            { Amach.Surface.bgDark }
    static var amachSurface: Color       { Amach.Surface.surfaceDark }
    static var amachElevated: Color      { Amach.Surface.elevatedDark }
    static var amachPrimary: Color       { Amach.p400 }
    static var amachAccent: Color        { Amach.accent }
    static var amachTextPrimary: Color   { Amach.Text.primaryD }
    static var amachTextSecondary: Color { Amach.Text.secondaryD }
    static var amachTextTertiary: Color  { Amach.Text.tertiaryD }
#endif

    static let amachPrimaryBright     = Amach.p400
    static var amachPrimaryWordmark: Color { amachPrimary }
    static let amachGold              = Amach.accent
    static let amachSilver            = Color(hex: "94A3B8")
    static let amachBronze            = Color(hex: "CD7F32")
    static let amachAI                = Amach.AI.base
    static let amachDestructive       = Amach.Semantic.error
    static let amachWarning           = Amach.Semantic.warning
    static let amachSuccess           = Amach.Semantic.success
}


// ============================================================
// MARK: - TYPOGRAPHY
// ============================================================

public enum AmachType {
    public static var h1: Font          { .system(size: 28, weight: .bold) }
    public static var companyName: Font { .system(size: 32, weight: .heavy) }
    public static var h2: Font          { .system(size: 20, weight: .semibold) }
    public static var h3: Font          { .system(size: 16, weight: .semibold) }
    public static var body: Font        { .system(size: 16, weight: .regular) }
    public static var caption: Font     { .system(size: 14, weight: .regular) }
    public static var tiny: Font        { .system(size: 12, weight: .medium) }

    public static func dataValue(size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }
    public static func dataUnit(size: CGFloat = 18) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
    public static var dataMono: Font { .system(size: 12, weight: .medium, design: .monospaced) }
}


// ============================================================
// MARK: - SPACING
// ============================================================

public enum AmachSpacing {
    public static let xs:   CGFloat = 4
    public static let sm:   CGFloat = 8
    public static let md:   CGFloat = 16
    public static let lg:   CGFloat = 24
    public static let xl:   CGFloat = 32
    public static let xxl:  CGFloat = 48
    public static let xxxl: CGFloat = 64

    public static let cardPadding:    CGFloat = 24
    public static let cardGap:        CGFloat = 16
    public static let sectionSpacing: CGFloat = 32
    public static let screenEdge:     CGFloat = 16
}


// ============================================================
// MARK: - CORNER RADIUS
// ============================================================

public enum AmachRadius {
    public static let xs:   CGFloat = 6
    public static let sm:   CGFloat = 10
    public static let md:   CGFloat = 14
    public static let card: CGFloat = 16
    public static let lg:   CGFloat = 20
    public static let xl:   CGFloat = 24
    public static let pill: CGFloat = 100
}


// ============================================================
// MARK: - ELEVATION
// ============================================================

public enum AmachElevation {
    public struct Level1 {
        public static let shadowColor    = Color.black.opacity(0.10)
        public static let shadowRadius:  CGFloat = 8
        public static let shadowX:       CGFloat = 0
        public static let shadowY:       CGFloat = 2
        public static let borderOpacity: Double  = 0.12
    }
    public struct Level2 {
        public static let shadowColor    = Color.black.opacity(0.18)
        public static let shadowRadius:  CGFloat = 16
        public static let shadowX:       CGFloat = 0
        public static let shadowY:       CGFloat = 6
        public static let borderOpacity: Double  = 0.20
    }
    public struct Level3 {
        public static let shadowColor     = Color.black.opacity(0.30)
        public static let shadowRadius:   CGFloat = 32
        public static let shadowX:        CGFloat = 0
        public static let shadowY:        CGFloat = 16
        public static let overlayOpacity: Double  = 0.40
    }
}


// ============================================================
// MARK: - ANIMATION
// ============================================================

public enum AmachAnimation {
    public static let durationFast:    Double = 0.15
    public static let durationNormal:  Double = 0.25
    public static let durationSlow:    Double = 0.40
    public static let durationChart:   Double = 0.80
    public static let durationCount:   Double = 0.50

    public static let fast:        Animation = .easeOut(duration: durationFast)
    public static let normal:      Animation = .easeOut(duration: durationNormal)
    public static let slow:        Animation = .easeInOut(duration: durationSlow)
    public static let spring:      Animation = .spring(response: 0.3, dampingFraction: 0.7)
    public static let sheetSpring: Animation = .spring(response: 0.35, dampingFraction: 0.85)
    public static let countUp:     Animation = .easeOut(duration: durationCount)
    public static let chartDraw:   Animation = .easeInOut(duration: durationChart)

    public static let cardPressScale:   CGFloat = 0.97
    public static let buttonPressScale: CGFloat = 0.96

    public static let lumaTypingDotDuration: Double = 0.6
    public static let lumaTypingStagger:     Double = 0.15

    public static func ifMotion(_ animation: Animation) -> Animation? {
#if os(iOS)
        UIAccessibility.isReduceMotionEnabled ? nil : animation
#else
        animation
#endif
    }
}


// ============================================================
// MARK: - HAPTICS
// ============================================================

public enum AmachHaptics {
#if os(iOS)
    public static func cardTap()      { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    public static func buttonPress()  { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    public static func success()      { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    public static func error()        { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    public static func toggle()       { UISelectionFeedbackGenerator().selectionChanged() }
    public static func pullRefresh()  { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    public static func lumaResponse() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
#elseif os(watchOS)
    public static func cardTap()      { WKInterfaceDevice.current().play(.click) }
    public static func buttonPress()  { WKInterfaceDevice.current().play(.click) }
    public static func success()      { WKInterfaceDevice.current().play(.success) }
    public static func error()        { WKInterfaceDevice.current().play(.failure) }
    public static func toggle()       { WKInterfaceDevice.current().play(.click) }
    public static func pullRefresh()  { WKInterfaceDevice.current().play(.click) }
    public static func lumaResponse() { WKInterfaceDevice.current().play(.click) }
#else
    // macOS — no-op (design system used in tests only)
    public static func cardTap()      {}
    public static func buttonPress()  {}
    public static func success()      {}
    public static func error()        {}
    public static func toggle()       {}
    public static func pullRefresh()  {}
    public static func lumaResponse() {}
#endif
}


// ============================================================
// MARK: - ACCESSIBILITY
// ============================================================

public enum AmachAccessibility {
    public static let minTouchTarget: CGFloat = 44
    public static let minBodySize: CGFloat = 16

    public static func isReduceMotionEnabled() -> Bool {
#if os(iOS)
        UIAccessibility.isReduceMotionEnabled
#else
        false
#endif
    }
}


// ============================================================
// MARK: - VIEW MODIFIERS
// ============================================================

public extension View {

    func amachCard() -> some View {
        self
            .background(Color.amachSurface)
            .clipShape(RoundedRectangle(cornerRadius: AmachRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: AmachRadius.card)
                    .stroke(Color.amachPrimary.opacity(AmachElevation.Level1.borderOpacity), lineWidth: 1)
            )
            .shadow(color: AmachElevation.Level1.shadowColor,
                    radius: AmachElevation.Level1.shadowRadius,
                    x: AmachElevation.Level1.shadowX,
                    y: AmachElevation.Level1.shadowY)
    }

    func amachCardElevated() -> some View {
        self
            .background(Color.amachElevated)
            .clipShape(RoundedRectangle(cornerRadius: AmachRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: AmachRadius.card)
                    .stroke(Color.amachPrimary.opacity(AmachElevation.Level2.borderOpacity), lineWidth: 1)
            )
            .shadow(color: AmachElevation.Level2.shadowColor,
                    radius: AmachElevation.Level2.shadowRadius,
                    x: AmachElevation.Level2.shadowX,
                    y: AmachElevation.Level2.shadowY)
    }

    func amachAIBorder(radius: CGFloat = AmachRadius.card) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: radius)
                .stroke(
                    LinearGradient(
                        colors: [Color.Amach.primary.opacity(0.6), Color.Amach.AI.base.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    func amachGlow() -> some View {
        self.shadow(color: Color.Amach.primary.opacity(0.35), radius: 12, x: 0, y: 4)
    }

    func amachAIGlow() -> some View {
        self.shadow(color: Color.Amach.AI.base.opacity(0.30), radius: 12, x: 0, y: 4)
    }

    func amachPressEffect(isPressed: Bool) -> some View {
        self
            .scaleEffect(isPressed ? AmachAnimation.cardPressScale : 1.0)
            .animation(AmachAnimation.spring, value: isPressed)
    }
}


// ============================================================
// MARK: - BUTTON STYLES (iOS only)
// ============================================================

#if os(iOS)
public struct AmachPrimaryButtonStyle: ButtonStyle {
    public var isLoading: Bool = false
    public init(isLoading: Bool = false) { self.isLoading = isLoading }

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: AmachSpacing.sm) {
            if isLoading {
                ProgressView()
                    .tint(Color.Amach.Text.onPrimary)
                    .scaleEffect(0.85)
            }
            configuration.label
        }
        .font(AmachType.h3)
        .fontWeight(.semibold)
        .padding(.horizontal, AmachSpacing.lg)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color.Amach.primary)
        .foregroundStyle(Color.Amach.Text.onPrimary)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
        .shadow(color: Color.Amach.primary.opacity(0.28), radius: 8, y: 2)
        .scaleEffect(configuration.isPressed ? AmachAnimation.buttonPressScale : 1)
        .animation(AmachAnimation.ifMotion(AmachAnimation.spring), value: configuration.isPressed)
        .onChange(of: configuration.isPressed) { _, pressed in
            if pressed { AmachHaptics.buttonPress() }
        }
    }
}

public struct AmachSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AmachType.h3)
            .fontWeight(.semibold)
            .padding(.horizontal, AmachSpacing.lg)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(.clear)
            .foregroundStyle(Color.amachPrimary)
            .overlay(
                RoundedRectangle(cornerRadius: AmachRadius.sm)
                    .stroke(Color.amachPrimary, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? AmachAnimation.cardPressScale : 1)
            .animation(AmachAnimation.ifMotion(AmachAnimation.spring), value: configuration.isPressed)
    }
}

public extension View {
    func amachPrimaryButtonStyle(isLoading: Bool = false) -> some View {
        buttonStyle(AmachPrimaryButtonStyle(isLoading: isLoading))
    }
    func amachSecondaryButtonStyle() -> some View {
        buttonStyle(AmachSecondaryButtonStyle())
    }
}
#endif


// ============================================================
// MARK: - HEALTH STATUS PILL
// ============================================================

public struct HealthStatusPill: View {

    public enum Status {
        case optimal, borderline, belowTrend, critical, noData

        public static func from(_ string: String) -> Status {
            switch string.lowercased() {
            case "optimal":     return .optimal
            case "borderline":  return .borderline
            case "below trend": return .belowTrend
            case "critical":    return .critical
            default:            return .noData
            }
        }
    }

    public let status: Status
    public init(status: Status) { self.status = status }

    private var label: String {
        switch status {
        case .optimal:    return "Optimal"
        case .borderline: return "Borderline"
        case .belowTrend: return "Below trend"
        case .critical:   return "Critical"
        case .noData:     return "No data"
        }
    }

    private var tint: Color {
        switch status {
        case .optimal:                 return Color.Amach.Health.optimal
        case .borderline, .belowTrend: return Color.Amach.Health.borderline
        case .critical:                return Color.Amach.Health.critical
        case .noData:                  return Color.Amach.Health.noData
        }
    }

    public var body: some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(label).font(AmachType.tiny).fontWeight(.semibold)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, AmachSpacing.sm)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }
}


// ============================================================
// MARK: - TIER BADGE
// ============================================================

public struct AmachTierBadge: View {
    public let tier: String
    public init(tier: String) { self.tier = tier }

    private var config: (bg: Color, text: Color, border: Color) {
        switch tier.uppercased() {
        case "GOLD":   return (Color.Amach.Tier.goldBg,   Color.Amach.Tier.goldText,   Color.Amach.Tier.goldBorder)
        case "SILVER": return (Color.Amach.Tier.silverBg, Color.Amach.Tier.silverText, Color.Amach.Tier.silverBorder)
        case "BRONZE": return (Color.Amach.Tier.bronzeBg, Color.Amach.Tier.bronzeText, Color.Amach.Tier.bronzeBorder)
        default:       return (Color.Amach.Tier.noneBg,   Color.Amach.Tier.noneText,   Color.Amach.Tier.noneBorder)
        }
    }

    public var body: some View {
        Text(tier.uppercased())
            .font(AmachType.tiny)
            .fontWeight(.bold)
            .tracking(0.5)
            .padding(.horizontal, AmachSpacing.sm)
            .padding(.vertical, 4)
            .background(config.bg)
            .foregroundStyle(config.text)
            .clipShape(RoundedRectangle(cornerRadius: AmachRadius.xs))
            .overlay(
                RoundedRectangle(cornerRadius: AmachRadius.xs)
                    .stroke(config.border, lineWidth: 1)
            )
    }
}


// ============================================================
// MARK: - ICON TOKENS
// ============================================================

public enum AmachIcon {
    public static let heartRate   = "heart.fill"
    public static let hrv         = "waveform.path.ecg"
    public static let breathe     = "wind"
    public static let sleep       = "moon.fill"
    public static let exercise    = "figure.run"
    public static let wallet      = "wallet.pass.fill"
    public static let storage     = "lock.shield.fill"
    public static let settings    = "gearshape.fill"
    public static let info        = "info.circle.fill"
    public static let warning     = "exclamationmark.triangle.fill"
    public static let errorIcon   = "xmark.circle.fill"
    public static let successIcon = "checkmark.circle.fill"
}
