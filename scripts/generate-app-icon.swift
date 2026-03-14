import AppKit
import Foundation

struct IconSpec {
    let filename: String
    let size: CGFloat
}

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
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(spec.size),
        pixelsHigh: Int(spec.size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: spec.size, height: spec.size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let canvas = NSRect(x: 0, y: 0, width: spec.size, height: spec.size)
    NSColor.clear.setFill()
    canvas.fill()

    let cornerRadius = spec.size * 0.26
    let backgroundRect = canvas.insetBy(dx: spec.size * 0.04, dy: spec.size * 0.04)
    let backgroundPath = NSBezierPath(
        roundedRect: backgroundRect,
        xRadius: cornerRadius,
        yRadius: cornerRadius
    )

    let gradient = NSGradient(
        colors: [
            NSColor(calibratedRed: 0.06, green: 0.11, blue: 0.18, alpha: 1),
            NSColor(calibratedRed: 0.08, green: 0.31, blue: 0.54, alpha: 1)
        ]
    )!
    gradient.draw(in: backgroundPath, angle: -35)

    NSColor.white.withAlphaComponent(0.08).setStroke()
    backgroundPath.lineWidth = max(1, spec.size * 0.015)
    backgroundPath.stroke()

    let barHeight = spec.size * 0.11
    let barRadius = barHeight / 2
    let barX = backgroundRect.minX + spec.size * 0.16
    let barYStart = backgroundRect.minY + spec.size * 0.21
    let barSpacing = spec.size * 0.08
    let bars: [(CGFloat, NSColor)] = [
        (spec.size * 0.34, NSColor.systemRed),
        (spec.size * 0.54, NSColor.systemOrange),
        (spec.size * 0.4, NSColor.systemGreen)
    ]

    for (index, bar) in bars.enumerated() {
        let rect = NSRect(
            x: barX,
            y: barYStart + CGFloat(index) * (barHeight + barSpacing),
            width: bar.0,
            height: barHeight
        )
        let path = NSBezierPath(roundedRect: rect, xRadius: barRadius, yRadius: barRadius)
        let barGradient = NSGradient(colors: [
            bar.1.withAlphaComponent(0.95),
            bar.1.withAlphaComponent(0.75)
        ])!
        barGradient.draw(in: path, angle: 0)
    }

    let badgeSize = spec.size * 0.22
    let badgeRect = NSRect(
        x: backgroundRect.maxX - badgeSize - spec.size * 0.11,
        y: backgroundRect.maxY - badgeSize - spec.size * 0.11,
        width: badgeSize,
        height: badgeSize
    )
    let badgePath = NSBezierPath(ovalIn: badgeRect)
    NSColor.white.withAlphaComponent(0.96).setFill()
    badgePath.fill()

    let innerDotSize = spec.size * 0.09
    let innerDotRect = NSRect(
        x: badgeRect.midX - innerDotSize / 2,
        y: badgeRect.midY - innerDotSize / 2,
        width: innerDotSize,
        height: innerDotSize
    )
    NSColor(calibratedRed: 0.01, green: 0.46, blue: 0.83, alpha: 1).setFill()
    NSBezierPath(ovalIn: innerDotRect).fill()

    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode \(spec.filename)")
    }

    try pngData.write(to: outputURL.appendingPathComponent(spec.filename))
}

print("Generated iconset at \(outputURL.path)")
