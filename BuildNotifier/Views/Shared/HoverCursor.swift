import SwiftUI
import AppKit

extension View {
    func pointingHandCursor() -> some View {
        cursor(.pointingHand)
    }

    /// Shows `cursor` while hovered. Uses the AppKit cursor stack (`push`/`pop`) rather
    /// than `set()` so the cursor survives view redraws - otherwise an animating sibling
    /// (e.g. the shimmer) resets it every frame and the pointer flickers.
    func cursor(_ cursor: NSCursor) -> some View {
        modifier(HoverCursor(cursor: cursor))
    }
}

private struct HoverCursor: ViewModifier {
    let cursor: NSCursor

    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    guard !pushed else { return }
                    cursor.push()
                    pushed = true
                } else {
                    guard pushed else { return }
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onDisappear {
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}
