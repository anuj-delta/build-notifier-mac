import AppKit
import SwiftUI

@MainActor
enum AppWindowManager {
    static func dismissActiveMenuBarWindow() {
        MenuBarItem.current?.close()
    }

    static func dismissActiveMenuBarWindow(then action: @MainActor @escaping () -> Void) {
        dismissActiveMenuBarWindow()
        Task { action() }
    }

    /// Every link in the menu goes through here, so the panel closes on the way out instead
    /// of hanging around behind the browser.
    static func openFromMenu(_ urlString: String?) {
        guard let urlString, let url = URL(string: urlString) else { return }
        dismissActiveMenuBarWindow {
            ExternalLink.open(url)
        }
    }

    // MARK: - Settings and setup windows

    private static var settings: NSWindow?
    private static var setup: NSWindow?

    static func openSettings(_ appState: AppState) {
        let window = settings ?? make(
            content: SettingsView(appState: appState),
            title: "Settings",
            autosaveName: "settings",
            size: NSSize(width: 860, height: 580),
            resizable: true
        )
        settings = window
        present(window)
    }

    static func closeSettings() {
        settings?.close()
    }

    static func openSetup(_ appState: AppState) {
        let window = setup ?? make(
            content: SetupWindowContent(appState: appState),
            title: "Setup",
            autosaveName: "onboarding",
            size: nil,
            resizable: false
        )
        setup = window
        present(window)
    }

    static func closeSetup() {
        setup?.close()
    }

    /// `size` nil sizes the window to its content, matching `.windowResizability(.contentSize)`.
    private static func make<Content: View>(
        content: Content,
        title: String,
        autosaveName: String,
        size: NSSize?,
        resizable: Bool
    ) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView]
        if resizable { style.insert(.resizable) }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size ?? NSSize(width: 100, height: 100)),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content)
        if let size { window.setContentSize(size) }
        window.center()
        _ = window.setFrameUsingName(autosaveName)
        window.setFrameAutosaveName(autosaveName)
        _ = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { syncDockIcon(closing: window) }
        }
        return window
    }

    private static func present(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        syncDockIcon()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Dock icon lifecycle

    /// The app runs as a menu-bar accessory with no dock icon. While a real window is up it
    /// becomes a regular app, so it earns a dock icon and normal window behaviour, and drops
    /// back once the last one closes.
    ///
    /// Derived from the windows rather than counted on the way in and out: these windows are
    /// reused, and `close()` leaves their SwiftUI content mounted, so view lifecycle never
    /// reports the close and the icon used to stay for the rest of the session. `closing` is
    /// the window inside `willClose`, which still reads as visible.
    private static func syncDockIcon(closing: NSWindow? = nil) {
        let wantsDockIcon = [settings, setup].contains { window in
            guard let window, window !== closing else { return false }
            return window.isVisible
        }
        let policy: NSApplication.ActivationPolicy = wantsDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }
}
