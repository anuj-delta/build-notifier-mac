import SwiftUI

/// The panel's answer when a provider has nothing to show: a glyph, one line that names the
/// state, one line that says what fills it, and the action that does so.
struct ProviderEmptyStateCard: View {
    let title: String
    let message: String
    var icon: String = "tray"
    var tint: Color = AppChrome.accent
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.12)))

            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppChrome.text)

                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(AppChrome.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(EmptyStateActionStyle(tint: tint))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background {
            RoundedRectangle(cornerRadius: AppChrome.radiusCard, style: .continuous)
                .fill(AppChrome.surfaceMuted)
                .overlay {
                    RoundedRectangle(cornerRadius: AppChrome.radiusCard, style: .continuous)
                        .stroke(AppChrome.separator, lineWidth: 1)
                }
        }
        .padding(.vertical, 6)
    }
}

/// One quiet line under a project header that has no rows of its own.
struct EmptySectionNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(AppChrome.textMuted.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.bottom, 4)
    }
}

private struct EmptyStateActionStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: AppChrome.radiusSmall, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.22 : 0.14))
            }
            .contentShape(Rectangle())
            .pointingHandCursor()
    }
}
