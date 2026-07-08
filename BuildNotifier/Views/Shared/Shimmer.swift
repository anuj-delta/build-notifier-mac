import SwiftUI

/// Sweeps a bright band across the content to signal an in-progress build.
/// Paints its own muted/highlight colors masked to the content's shape, so it
/// works regardless of any `foregroundStyle` the caller already set on the
/// label. Honors Reduce Motion with a static muted fallback.
struct Shimmer: ViewModifier {
    var active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        if !active {
            content
        } else if reduceMotion {
            content.foregroundStyle(AppChrome.textMuted)
        } else {
            content
                .hidden()
                .overlay(
                    GeometryReader { geo in
                        let w = max(geo.size.width, 1)
                        ZStack {
                            AppChrome.textMuted
                            AppChrome.text
                                .mask(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.clear, .black, .clear]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .frame(width: w * 0.55)
                                    .offset(x: -w * 0.9 + phase * (w * 1.8))
                                )
                        }
                        .mask(content)
                    }
                    .allowsHitTesting(false)
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        }
    }
}

extension View {
    func shimmering(active: Bool) -> some View {
        modifier(Shimmer(active: active))
    }
}
