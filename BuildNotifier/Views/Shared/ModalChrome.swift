import SwiftUI

enum ModalActionKind {
    case primary
    case destructive
    case secondary
}

/// Full-height action button used inside modal overlays. Filled accent/danger for
/// the confirming action, a calm glass panel for the secondary choice.
struct ModalActionButtonStyle: ButtonStyle {
    let kind: ModalActionKind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppChrome.radiusMedium, style: .continuous)
        let pressed = configuration.isPressed

        return configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .foregroundStyle(foreground)
            .background(shape.fill(fill(pressed: pressed)))
            .overlay(shape.strokeBorder(stroke, lineWidth: 1))
            .clipShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(pressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .destructive:
            return .white
        case .secondary:
            return AppChrome.text
        }
    }

    private func fill(pressed: Bool) -> Color {
        switch kind {
        case .primary:
            return AppChrome.accent.opacity(pressed ? 0.82 : 1)
        case .destructive:
            return AppChrome.danger.opacity(pressed ? 0.82 : 1)
        case .secondary:
            return pressed ? AppChrome.rowHover : AppChrome.glassPanel
        }
    }

    private var stroke: Color {
        switch kind {
        case .primary, .destructive:
            return .clear
        case .secondary:
            return AppChrome.glassStroke
        }
    }
}

extension View {
    /// Frosted card surface for centered modal overlays, matching the popover's
    /// glass language: translucent material, single hairline edge, soft drop shadow.
    func modalSurface(width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return self
            .frame(width: width)
            .background(shape.fill(AppChrome.surface.opacity(0.55)))
            .background(shape.fill(.regularMaterial))
            .overlay(shape.strokeBorder(AppChrome.glassStroke, lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.28), radius: 26, y: 12)
    }
}

/// Dimming scrim behind a modal overlay. Taps outside the card dismiss unless blocked.
struct ModalScrim: View {
    var isDismissable: Bool = true
    let onDismiss: () -> Void

    var body: some View {
        Rectangle()
            .fill(.black.opacity(0.34))
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { if isDismissable { onDismiss() } }
    }
}
