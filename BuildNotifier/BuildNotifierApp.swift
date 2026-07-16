import SwiftUI
import AppKit
import Sentry

@main
struct BuildNotifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    init() {
        // DSN comes from the SENTRY_DSN env var (dev / `swift run`) or the
        // SentryDSN Info.plist key baked in at build time (packaged .app, which
        // can't read shell env). Skip init entirely when neither is set.
        guard let dsn = Self.sentryDSN else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            options.sendDefaultPii = true
            options.debug = ProcessInfo.processInfo.environment["SENTRY_DEBUG"] == "1"
        }
    }

    private static var sentryDSN: String? {
        let candidates = [
            ProcessInfo.processInfo.environment["SENTRY_DSN"],
            Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    var body: some Scene {
        // Menu Bar
        MenuBarExtra {
            MenuBarExtraContent(appState: appState)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)
        
        // Settings Window
        Window("Settings", id: "settings") {
            SettingsView(appState: appState)
        }
        .defaultSize(width: 860, height: 580)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        
        // Onboarding Window
        Window("Setup", id: "onboarding") {
            OnboardingWindowContent(appState: appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - App Delegate for hiding dock icon

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - run as menubar-only app
        NSApp.setActivationPolicy(.accessory)
        if let icon = AppBrandAssets.applicationIcon() {
            NSApp.applicationIconImage = icon
        }
    }
}

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    @Bindable var appState: AppState

    var body: some View {
        Group {
            if !appState.pendingApprovals.isEmpty {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 16, height: 14)
            } else if appState.hasActiveBuildActivity {
                if appState.preferences.showDeployLoader {
                    MenuBarDeployingGlyph(
                        style: appState.preferences.deployLoaderStyle,
                        phase: appState.deploySpinnerPhase
                    )
                } else {
                    MenuBarSpinnerGlyph()
                }
            } else {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 16, height: 14)
            }
        }
        .accessibilityLabel(menuBarAccessibilityLabel)
    }

    private var menuBarAccessibilityLabel: String {
        if !appState.pendingApprovals.isEmpty {
            return "Approval pending"
        }
        if appState.isDeploying {
            return "Deploying"
        }
        return appState.hasActiveBuildActivity ? "Builds running" : "Idle"
    }
}

/// Static build-activity glyph. The status bar can't animate a plain SwiftUI
/// rotation, and animation here is intentionally reserved for the deploy loader,
/// so this stays a still icon.
struct MenuBarSpinnerGlyph: View {
    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .symbolRenderingMode(.monochrome)
            .frame(width: 16, height: 14)
    }
}

/// The look of the deploy-in-flight menu bar spinner. User-selectable in Settings.
enum MenuBarDeployStyle: String, CaseIterable, Codable {
    case arc, dots, dashes, arrows

    var label: String {
        switch self {
        case .arc: return "Arc sweep"
        case .dots: return "Chasing dots"
        case .dashes: return "Slowmo dashes"
        case .arrows: return "Refresh arrows"
        }
    }
}

/// A deploy-in-flight spinner. `MenuBarExtra` only redraws the status item when
/// the icon's *content* changes (the same reason the idle/spinner/approval swap
/// works) - a `rotationEffect` transform on the same image is invisible to it.
/// So each frame renders the glyph rotated by `phase` into a fresh template
/// `NSImage`; the new image content per tick reads like a swap and redraws.
/// `phase` comes from `AppState`, advanced by a timer, so the label re-renders.
/// arc/dots are hand-drawn with Core Graphics; dashes/arrows are SF Symbols.
struct MenuBarDeployingGlyph: View {
    let style: MenuBarDeployStyle
    let phase: Double

    var body: some View {
        Image(nsImage: Self.frame(style: style, degrees: phase * 360))
            .frame(width: 16, height: 14)
    }

    private static let side: CGFloat = 15

    private static func frame(style: MenuBarDeployStyle, degrees: Double) -> NSImage {
        switch style {
        case .dashes: return rotatedSymbol("slowmo", degrees: degrees)
        case .arrows: return rotatedSymbol("arrow.triangle.2.circlepath", degrees: degrees)
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

    private static func rotatedSymbol(_ name: String, degrees: Double) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: "Deploying")?
            .withSymbolConfiguration(config), base.size.width > 0 else { return NSImage() }
        let image = NSImage(size: base.size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: -CGFloat(degrees) * .pi / 180)
            ctx.translateBy(x: -rect.midX, y: -rect.midY)
            base.draw(in: rect)
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
}

// MARK: - Menu Bar Extra Content

struct MenuBarExtraContent: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        Group {
            switch appState.currentScreen {
            case .loading:
                LoadingView()
                    .task {
                        await appState.initialize()
                    }
                
            case .onboarding:
                PopoverWelcomeCard(
                    title: "Setup required",
                    subtitle: "Connect CircleCI or skip into Settings to add integrations later.",
                    buttonTitle: "Open Setup",
                    action: {
                        AppWindowManager.dismissActiveMenuBarWindow {
                            openWindow(id: "onboarding")
                            NSApplication.shared.activate(ignoringOtherApps: true)
                        }
                    }
                )
                
            case .projectSelection:
                PopoverWelcomeCard(
                    title: "Choose projects",
                    subtitle: "Pick the CircleCI repositories you want to watch from the menu bar.",
                    buttonTitle: "Open Project Selector",
                    action: {
                        AppWindowManager.dismissActiveMenuBarWindow {
                            openWindow(id: "onboarding")
                            NSApplication.shared.activate(ignoringOtherApps: true)
                        }
                    }
                )
                
            case .main:
                MenuBarContentView(appState: appState)
            }
        }
    }
}

// MARK: - Onboarding Window Content

struct OnboardingWindowContent: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Group {
            switch appState.currentScreen {
            case .onboarding:
                OnboardingView(appState: appState)
                
            case .projectSelection:
                ProjectSelectorView(appState: appState)
                
            default:
                VStack(spacing: 16) {
                    AppBrandIcon(size: 54)
                    
                    Text("Setup Complete!")
                        .font(.headline)
                    
                    Text("You can close this window")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(32)
                .frame(width: 300, height: 200)
            }
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            AppBrandIcon(size: 44)
                .opacity(0.92)

            ProgressView()

            Text("Loading your build status")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 220)
    }
}

struct PopoverWelcomeCard: View {
    let title: String
    let subtitle: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            AppBrandIcon(size: 48)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(buttonTitle) {
                action()
            }
            .buttonStyle(.borderedProminent)

            Divider()
                .padding(.vertical, 2)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 300)
    }
}
