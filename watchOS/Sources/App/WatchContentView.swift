import SwiftUI
import AmachBreatheShared

struct WatchContentView: View {
    var body: some View {
        VStack(spacing: AmachSpacing.sm) {
            Image(systemName: AmachIcon.breathe)
                .font(.system(size: AmachType.iconBase))
                .foregroundStyle(Color.amachPrimary)
            Text("Amach Breathe")
                .font(AmachType.brandLabel)
                .tracking(2.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.amachTextSecondary)
                .amachShimmer(delay: 0.6)
        }
    }
}

#Preview {
    WatchContentView()
}
