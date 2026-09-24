import SwiftUI
import AppKit

/// The status item icon. This is AppKit rather than SwiftUI so the button keeps its
/// own `image`, which is what lets macOS draw the standard menu bar highlight
/// behind it while the menu is open.
enum MenuBarGlyph {
    @MainActor
    static func image(for appState: AppState) -> NSImage {
        if !appState.pendingApprovals.isEmpty {
            return approval
        }
        guard appState.hasActiveBuildActivity else {
            return symbol("circle.dashed")
        }
        guard appState.preferences.showDeployLoader else {
            return symbol("arrow.triangle.2.circlepath")
        }
        return deploying(style: appState.preferences.deployLoaderStyle, phase: appState.deploySpinnerPhase)
    }

    @MainActor
    static func accessibilityLabel(for appState: AppState) -> String {
        if !appState.pendingApprovals.isEmpty {
            return "Approval pending"
        }
        if appState.isDeploying {
            return "Deploying"
        }
        return appState.hasActiveBuildActivity ? "Builds running" : "Idle"
    }

    // MARK: - Frames

    private static let pointSize: CGFloat = 13
    private static let side: CGFloat = 15

    private static var approval: NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: .systemOrange))
        guard let image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "Approval pending")?
            .withSymbolConfiguration(config) else { return NSImage() }
        image.isTemplate = false
        return image
    }

    private static func symbol(_ name: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return NSImage() }
        image.isTemplate = true
        return image
    }

    /// Timer steps per turn. The arc draws one frame per step; the 12-spoke styles advance
    /// one spoke every other step, since a spoke drawn between slots reads as a wobble.
    static let spinnerFrames = 24
    static let spinnerPeriod = 0.9

    @MainActor private static var frameCache: [MenuBarDeployStyle: [NSImage]] = [:]

    /// The deploy spinner frame nearest `phase` (0...1). Frames are drawn once per style.
    @MainActor
    static func deploying(style: MenuBarDeployStyle, phase: Double) -> NSImage {
        let count = style == .arc ? spinnerFrames : 12
        let frames = frameCache[style] ?? (0..<count).map { i in
            render(style: style, degrees: Double(i) * 360 / Double(count))
        }
        frameCache[style] = frames
        let step = Int((phase * Double(spinnerFrames)).rounded())
        let wrapped = (step % spinnerFrames + spinnerFrames) % spinnerFrames
        return frames[wrapped * count / spinnerFrames]
    }

    private static func render(style: MenuBarDeployStyle, degrees: Double) -> NSImage {
        switch style {
        case .dashes: return rotated(degrees: degrees, draw: drawDashes)
        case .arc: return rotated(degrees: degrees, draw: drawArc)
        case .dots: return rotated(degrees: degrees, draw: drawDots)
        }
    }

    /// Renders `draw` into a template image, rotated clockwise by `degrees`
    /// (negative CG angle in this bottom-left space) to match the row spinner.
    private static func rotated(degrees: Double, draw: @escaping (CGContext, CGRect) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: -CGFloat(degrees) * .pi / 180)
            ctx.translateBy(x: -rect.midX, y: -rect.midY)
            draw(ctx, rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// A rounded 270-degree arc with a gap - the headless "arc sweep".
    private static func drawArc(_ ctx: CGContext, _ rect: CGRect) {
        let lineWidth: CGFloat = 1.7
        let radius = min(rect.width, rect.height) / 2 - lineWidth
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: .pi / 2,
            endAngle: .pi / 2 - 2 * .pi * 0.75,
            clockwise: true
        )
        ctx.strokePath()
    }

    /// Twelve dots around a ring with graduated alpha so a bright head fades to a
    /// tail; rotating the whole thing makes the head chase around.
    private static func drawDots(_ ctx: CGContext, _ rect: CGRect) {
        let count = 12
        let radius = min(rect.width, rect.height) / 2 - 2
        let dot: CGFloat = 2.1
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for i in 0..<count {
            let angle = CGFloat.pi / 2 + CGFloat(i) / CGFloat(count) * 2 * .pi
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            let alpha = 0.14 + 0.86 * Double(i) / Double(count - 1)
            ctx.setFillColor(NSColor(white: 0, alpha: alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot))
        }
    }

    /// Twelve spokes with the same fading tail as `drawDots`.
    private static func drawDashes(_ ctx: CGContext, _ rect: CGRect) {
        let count = 12
        let outer = min(rect.width, rect.height) / 2 - 1
        let inner = outer * 0.55
        let center = CGPoint(x: rect.midX, y: rect.midY)
        ctx.setLineWidth(1.6)
        ctx.setLineCap(.round)
        for i in 0..<count {
            let angle = CGFloat.pi / 2 + CGFloat(i) / CGFloat(count) * 2 * .pi
            let alpha = 0.14 + 0.86 * Double(i) / Double(count - 1)
            ctx.setStrokeColor(NSColor(white: 0, alpha: alpha).cgColor)
            ctx.move(to: CGPoint(x: center.x + inner * cos(angle), y: center.y + inner * sin(angle)))
            ctx.addLine(to: CGPoint(x: center.x + outer * cos(angle), y: center.y + outer * sin(angle)))
            ctx.strokePath()
        }
    }
}

/// The look of the deploy-in-flight menu bar spinner. User-selectable in Settings.
enum MenuBarDeployStyle: String, CaseIterable, Codable {
    case arc, dots, dashes

    var label: String {
        switch self {
        case .arc: return "Arc sweep"
        case .dots: return "Chasing dots"
        case .dashes: return "Chasing dashes"
        }
    }
}

/// Preview of one spinner style, for the Settings picker.
struct MenuBarDeployingGlyph: View {
    let style: MenuBarDeployStyle
    let phase: Double

    var body: some View {
        Image(nsImage: MenuBarGlyph.deploying(style: style, phase: phase))
            .frame(width: 16, height: 14)
    }
}
