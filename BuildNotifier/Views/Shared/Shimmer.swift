import SwiftUI

/// Sweeps a bright band across the content to signal an in-progress build.
/// Paints its own muted/highlight colors masked to the content's shape, so it
/// works regardless of any `foregroundStyle` the caller already set on the
/// label. Honors Reduce Motion with a static muted fallback.
struct Shimmer: ViewModifier {
    var active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let period: TimeInterval = 1.8
    /// Share of the period spent sweeping; the remainder is a rest between sweeps.
    private let sweepShare: CGFloat = 0.72
    private let bandWidth: CGFloat = 0.7

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
                        // Driven by the clock, not a repeatForever animation started in
                        // onAppear: the menu panel is built once, so onAppear never fires
                        // again for a build that starts while the menu is closed.
                        TimelineView(.animation) { timeline in
                            let elapsed = timeline.date.timeIntervalSinceReferenceDate
                            ZStack {
                                AppChrome.textMuted
                                AppChrome.text
                                    .mask(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                .clear,
                                                .black.opacity(0.35),
                                                .black,
                                                .black.opacity(0.35),
                                                .clear
                                            ]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                        .frame(width: w * bandWidth)
                                        .offset(x: offset(at: elapsed, width: w))
                                    )
                            }
                            .mask(content)
                        }
                    }
                    .allowsHitTesting(false)
                )
        }
    }

    /// Eased sweep from fully off the leading edge to fully off the trailing edge,
    /// so the band never pops into view or snaps back at the wrap.
    private func offset(at elapsed: TimeInterval, width: CGFloat) -> CGFloat {
        let cycle = CGFloat(elapsed.truncatingRemainder(dividingBy: period) / period)
        let travel = min(cycle / sweepShare, 1)
        let eased = travel * travel * (3 - 2 * travel)
        let edge = width * (1 + bandWidth) / 2
        return -edge + eased * edge * 2
    }
}

extension View {
    func shimmering(active: Bool) -> some View {
        modifier(Shimmer(active: active))
    }
}
