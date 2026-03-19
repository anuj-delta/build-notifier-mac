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
}
