import AppKit
import Sentry

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private var menuBar: MenuBarItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        startSentry()

        installMainMenu()
        NSApp.setActivationPolicy(.accessory)
        if let icon = AppBrandAssets.applicationIcon() {
            NSApp.applicationIconImage = icon
        }

        menuBar = MenuBarItem(appState: appState)

        Task { await appState.initialize() }
    }

    /// An accessory app shows no menu bar, but `NSApp.mainMenu` is still what turns
    /// ⌘V and friends into responder-chain actions. Without it, text fields in the
    /// menu and in Settings cannot paste.
    private func installMainMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let app = NSMenu()
        app.addItem(withTitle: "Quit Build Notifier", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let main = NSMenu()
        for submenu in [app, edit] {
            let item = NSMenuItem()
            item.submenu = submenu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }

    private func startSentry() {
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
}
