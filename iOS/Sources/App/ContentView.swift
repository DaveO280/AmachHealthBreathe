import SwiftUI
import AmachBreatheShared

struct ContentView: View {
    var body: some View {
        ZStack {
            Color.amachBg.ignoresSafeArea()
            VStack(spacing: AmachSpacing.lg) {
                Image(systemName: AmachIcon.breathe)
                    .font(.system(size: 56))
                    .foregroundStyle(Color.amachPrimary)
                    .amachGlow()
                Text("Amach Breathe")
                    .font(AmachType.companyName)
                    .foregroundStyle(Color.amachTextPrimary)
                Text("Phase 0 scaffold")
                    .font(AmachType.caption)
                    .foregroundStyle(Color.amachTextSecondary)
            }
        }
    }
}

#Preview {
    ContentView()
}
