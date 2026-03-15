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
                .fill(backgroundGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: max(1, size * 0.018))
                }

            Circle()
                .fill(Color.white.opacity(0.16))
                .frame(width: size * 0.72, height: size * 0.72)
                .blur(radius: size * 0.09)
                .offset(x: size * 0.14, y: size * 0.16)

            cloud
        }
        .frame(width: size, height: size)
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
