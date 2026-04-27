import SwiftUI

// Faithfully replicates the shimmer from AmachHealth-iOS BrandComponents.swift.
// A silver light-sweep animates left-to-right continuously, masked to the text shape.
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
                            Color(hex: "CBD5E1").opacity(0.70),
                            Color.white.opacity(0.85),
                            Color(hex: "CBD5E1").opacity(0.70),
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
    /// Applies a continuous silver light-sweep over this view, matching the Amach wordmark shimmer.
    func amachShimmer(duration: Double = 4.5, delay: Double = 0.6) -> some View {
        modifier(AmachShimmerModifier(duration: duration, delay: delay))
    }
}
