import SwiftUI

// Amber light-sweep animates left-to-right continuously, masked to the text shape.
// Use .amachShimmer() on any Text that carries the Amach brand name.
struct AmachShimmerModifier: ViewModifier {

    @State private var phase: CGFloat = 0
    var duration: Double = 4.5
    var delay: Double    = 0.6

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let w      = geo.size.width
                    let stripW = w * 0.65
                    let startX = -stripW
                    let travel = w + stripW

                    LinearGradient(
                        colors: [
                            .clear,
                            Color(hex: "F59E0B").opacity(0.60),
                            Color(hex: "FCD34D").opacity(0.85),
                            Color(hex: "F59E0B").opacity(0.60),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint:   .trailing
                    )
                    .frame(width: stripW)
                    .offset(x: startX + phase * travel)
                }
                .mask(content)
                .clipped()
            )
            .onAppear {
                // Dispatching async avoids cancellation by concurrent entrance transitions.
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(
                        .linear(duration: duration)
                        .repeatForever(autoreverses: false)
                    ) {
                        phase = 1
                    }
                }
            }
    }
}

public extension View {
    func amachShimmer(duration: Double = 4.5, delay: Double = 0.6) -> some View {
        modifier(AmachShimmerModifier(duration: duration, delay: delay))
    }
}
