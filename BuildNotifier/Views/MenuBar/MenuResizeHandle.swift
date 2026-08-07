import SwiftUI
import AppKit

/// Drag the bottom edge to set how tall the menu is. The panel hangs from the menu bar, so
/// dragging down grows it and its top edge stays under the icon.
struct MenuResizeHandle: View {
    @Environment(MenuMetrics.self) private var metrics

    @State private var startHeight: CGFloat?
    @State private var isHovered = false

    var body: some View {
        Capsule()
            .fill(isActive ? AppChrome.textMuted : AppChrome.border)
            .frame(width: 34, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            .padding(.bottom, 5)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .cursor(.resizeUpDown)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        let start = startHeight ?? metrics.height
                        startHeight = start
                        metrics.resize(to: start + drag.translation.height)
                    }
                    .onEnded { _ in
                        startHeight = nil
                        metrics.save()
                    }
            )
            .animation(Motion.hover, value: isActive)
            .help("Drag to resize")
            .accessibilityHidden(true)
    }

    private var isActive: Bool {
        isHovered || startHeight != nil
    }
}
