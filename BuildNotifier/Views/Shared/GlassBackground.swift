import SwiftUI
import AppKit

/// Translucent material backing for the menu bar popover. Rounds its own layer so
/// the behind-window blur is masked to the popover shape rather than a square.
struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var cornerRadius: CGFloat = 13

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.layer?.cornerRadius = cornerRadius
    }
}

extension View {
    /// Calm translucent panel over a glass surface: a single hairline edge, no
    /// stacked frame. Shared by Settings sections and onboarding cards.
    func glassCard(cornerRadius: CGFloat = AppChrome.radiusMedium, selected: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(shape.fill(selected ? AppChrome.accentSoft : AppChrome.glassPanel))
            .overlay(shape.strokeBorder(selected ? AppChrome.accent.opacity(0.55) : AppChrome.glassStroke, lineWidth: 1))
            .clipShape(shape)
    }
}

/// Makes the hosting popover window transparent so the glass material can blur
/// what's behind it and the rounded corners read cleanly without a black box.
struct MenuWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}
