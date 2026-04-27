import SwiftUI
import AmachBreatheShared

struct WatchContentView: View {
    var body: some View {
        VStack(spacing: AmachSpacing.sm) {
            Image(systemName: AmachIcon.breathe)
                .font(.system(size: 32))
                .foregroundStyle(Color.amachPrimary)
            Text("Amach Breathe")
                .font(AmachType.h3)
                .foregroundStyle(Color.amachTextPrimary)
        }
    }
}

#Preview {
    WatchContentView()
}
