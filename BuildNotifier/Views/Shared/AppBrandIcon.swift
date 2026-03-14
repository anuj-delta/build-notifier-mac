import SwiftUI

struct AppBrandIcon: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.08, blue: 0.16),
                            Color(red: 0.10, green: 0.20, blue: 0.33),
                            Color(red: 0.09, green: 0.34, blue: 0.48)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: max(1, size * 0.018))
                }

            Circle()
                .fill(Color(red: 0.17, green: 0.63, blue: 0.78).opacity(0.28))
                .frame(width: size * 0.72, height: size * 0.72)
                .blur(radius: size * 0.06)
                .offset(x: size * 0.16, y: size * 0.12)

            cloud
                .offset(x: -size * 0.03, y: -size * 0.08)

            hammer
                .offset(x: size * 0.1, y: size * 0.1)

            spark
                .offset(x: size * 0.2, y: -size * 0.18)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.12), radius: size * 0.08, y: size * 0.03)
    }

    private var cloud: some View {
        ZStack(alignment: .bottomLeading) {
            Capsule(style: .continuous)
                .fill(cloudGradient)
                .frame(width: size * 0.48, height: size * 0.18)
                .offset(y: size * 0.05)

            Circle()
                .fill(cloudGradient)
                .frame(width: size * 0.24, height: size * 0.24)
                .offset(x: size * 0.02, y: -size * 0.02)

            Circle()
                .fill(cloudGradient)
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(x: size * 0.18, y: -size * 0.08)

            Circle()
                .fill(cloudGradient)
                .frame(width: size * 0.18, height: size * 0.18)
                .offset(x: size * 0.32, y: -size * 0.01)
        }
        .frame(width: size * 0.56, height: size * 0.3)
        .overlay(alignment: .bottomLeading) {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: max(1, size * 0.014))
                .frame(width: size * 0.48, height: size * 0.18)
                .offset(y: size * 0.05)
        }
    }

    private var hammer: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.90, green: 0.60, blue: 0.18),
                            Color(red: 0.66, green: 0.35, blue: 0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.11, height: size * 0.42)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: max(1, size * 0.01))
                }

            RoundedRectangle(cornerRadius: size * 0.05, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.98, blue: 1.0),
                            Color(red: 0.74, green: 0.82, blue: 0.91)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.33, height: size * 0.11)
                .offset(y: -size * 0.12)

            RoundedRectangle(cornerRadius: size * 0.03, style: .continuous)
                .fill(Color(red: 0.82, green: 0.88, blue: 0.95))
                .frame(width: size * 0.13, height: size * 0.07)
                .offset(x: size * 0.11, y: -size * 0.12)
        }
        .rotationEffect(.degrees(-32))
        .shadow(color: .black.opacity(0.12), radius: size * 0.04, y: size * 0.02)
    }

    private var spark: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color(red: 1.0, green: 0.85, blue: 0.42))
                .frame(width: size * 0.06, height: size * 0.16)

            Capsule(style: .continuous)
                .fill(Color(red: 1.0, green: 0.85, blue: 0.42))
                .frame(width: size * 0.16, height: size * 0.06)
        }
        .shadow(color: Color(red: 1.0, green: 0.85, blue: 0.42).opacity(0.35), radius: size * 0.04)
    }

    private var cloudGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.95),
                Color(red: 0.79, green: 0.89, blue: 0.96)
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
