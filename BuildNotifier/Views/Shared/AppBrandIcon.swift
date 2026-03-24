import SwiftUI

struct AppBrandIcon: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(backgroundGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: max(1, size * 0.016))
                }

            Circle()
                .fill(Color.white.opacity(0.16))
                .frame(width: size * 0.72, height: size * 0.72)
                .blur(radius: size * 0.09)
                .offset(x: size * 0.14, y: size * 0.16)

            cloud
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.08), radius: size * 0.05, y: size * 0.02)
    }

    private var cloud: some View {
        ZStack(alignment: .bottomLeading) {
            Capsule(style: .continuous)
                .fill(cloudGradient)
                .frame(width: size * 0.56, height: size * 0.21)
                .offset(y: size * 0.07)

            Circle()
                .fill(cloudGradient)
                .frame(width: size * 0.29, height: size * 0.29)
                .offset(x: size * 0.04, y: size * 0.01)

            Circle()
                .fill(cloudGradient)
                .frame(width: size * 0.25, height: size * 0.25)
                .offset(x: size * 0.23, y: -size * 0.08)

            Circle()
                .fill(cloudGradient)
                .frame(width: size * 0.19, height: size * 0.19)
                .offset(x: size * 0.40, y: size * 0.01)
        }
        .frame(width: size * 0.64, height: size * 0.36)
        .shadow(color: .white.opacity(0.12), radius: size * 0.05, y: size * 0.02)
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.32, blue: 0.74),
                Color(red: 0.15, green: 0.56, blue: 0.90),
                Color(red: 0.33, green: 0.76, blue: 0.97)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cloudGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.98),
                Color(red: 0.86, green: 0.94, blue: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
