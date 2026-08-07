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
        // Restores the frame saved by the SwiftUI scenes these windows replaced.
        window.setFrameAutosaveName(autosaveName)
        return window
    }

    private static func present(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Dock icon lifecycle

    private static var openAppWindowCount = 0

    /// The app runs as a menu-bar accessory (no dock icon). While a real window like Settings
    /// or onboarding is open, flip to a regular app so it earns a dock icon and normal window
    /// behaviour, then drop back to accessory once the last such window closes. Reference
    /// counted so both windows can be open at once without the icon flickering.
    static func appWindowAppeared() {
        openAppWindowCount += 1
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    static func appWindowDisappeared() {
        openAppWindowCount = max(0, openAppWindowCount - 1)
        if openAppWindowCount == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
