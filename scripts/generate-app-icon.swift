import AppKit
import Foundation
import SwiftUI

struct IconSpec {
    let filename: String
    let size: CGFloat
}

struct GeneratedAppBrandIcon: View {
    let size: CGFloat

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
func generateIconset() throws {
    let specs: [IconSpec] = [
        .init(filename: "icon_16x16.png", size: 16),
        .init(filename: "icon_16x16@2x.png", size: 32),
        .init(filename: "icon_32x32.png", size: 32),
        .init(filename: "icon_32x32@2x.png", size: 64),
        .init(filename: "icon_128x128.png", size: 128),
        .init(filename: "icon_128x128@2x.png", size: 256),
        .init(filename: "icon_256x256.png", size: 256),
        .init(filename: "icon_256x256@2x.png", size: 512),
        .init(filename: "icon_512x512.png", size: 512),
        .init(filename: "icon_512x512@2x.png", size: 1024)
    ]

    let fileManager = FileManager.default
    let outputURL = URL(fileURLWithPath: "BuildNotifier/Assets/AppIcon.iconset", isDirectory: true)

    try? fileManager.removeItem(at: outputURL)
    try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

    for spec in specs {
        let renderer = ImageRenderer(content: GeneratedAppBrandIcon(size: spec.size))
        renderer.scale = 1

        guard let image = renderer.nsImage,
              let tiffData = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            fatalError("Failed to render \(spec.filename)")
        }

        try pngData.write(to: outputURL.appendingPathComponent(spec.filename))
    }

    print("Generated iconset at \(outputURL.path)")
}

var generationError: Error?

Task { @MainActor in
    do {
        try generateIconset()
    } catch {
        generationError = error
    }
    CFRunLoopStop(CFRunLoopGetMain())
}

CFRunLoopRun()

if let generationError {
    throw generationError
}
