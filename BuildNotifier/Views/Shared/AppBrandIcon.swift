import SwiftUI

struct AppBrandIcon: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.06, green: 0.11, blue: 0.18),
                            Color(red: 0.08, green: 0.31, blue: 0.54)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: size * 0.09) {
                statusBar(width: 0.54, color: .green)
                statusBar(width: 0.74, color: .orange)
                statusBar(width: 0.46, color: .red)
            }
            .padding(size * 0.2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            Circle()
                .fill(.white.opacity(0.96))
                .frame(width: size * 0.26, height: size * 0.26)
                .overlay {
                    Circle()
                        .fill(Color(red: 0.01, green: 0.46, blue: 0.83))
                        .frame(width: size * 0.11, height: size * 0.11)
                }
                .padding(size * 0.12)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.12), radius: size * 0.08, y: size * 0.03)
    }

    private func statusBar(width: CGFloat, color: Color) -> some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.95), color.opacity(0.72)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: size * width, height: size * 0.12)
    }
}

@MainActor
enum AppBrandAssets {
    static func applicationIcon(size: CGFloat = 512) -> NSImage? {
        let renderer = ImageRenderer(content: AppBrandIcon(size: size))
        renderer.scale = 2
        return renderer.nsImage
    }
}
