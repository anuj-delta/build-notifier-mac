import AppKit

enum AppWindowManager {
    static func dismissActiveMenuBarWindow() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        window.orderOut(nil)
    }

    static func dismissActiveMenuBarWindow(then action: @escaping () -> Void) {
        dismissActiveMenuBarWindow()
        DispatchQueue.main.async(execute: action)
    }

    // MARK: - Dock icon lifecycle

    private static var openAppWindowCount = 0

    /// The app runs as a menu-bar accessory (no dock icon). While a real window like Settings
    /// or onboarding is open, flip to a regular app so it earns a dock icon and normal window
    /// behaviour, then drop back to accessory once the last such window closes. Reference
    /// counted so both windows can be open at once without the icon flickering.
    @MainActor static func appWindowAppeared() {
        openAppWindowCount += 1
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @MainActor static func appWindowDisappeared() {
        openAppWindowCount = max(0, openAppWindowCount - 1)
        if openAppWindowCount == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
