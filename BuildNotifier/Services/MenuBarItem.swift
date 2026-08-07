import AppKit
import SwiftUI

/// The menu bar icon and the panel it opens.
///
/// AppKit owns the status item rather than SwiftUI's `MenuBarExtra`, because that
/// API terminates the process when macOS asks the item to hide - exit code 0, no
/// crash log. Control Center hides an item whenever the app that launched it is
/// denied under "Allow in the Menu Bar", so a menu bar app must survive it.
/// How tall the menu content may grow. The window knows which screen it is on, the
/// content does not, so the window owns this and the content reads it.
@Observable
@MainActor
final class MenuMetrics {
    var heightBudget: CGFloat = 560
}

@MainActor
final class MenuBarItem: NSObject {
    static private(set) var current: MenuBarItem?

    private let appState: AppState
    private let item: NSStatusItem
    private let panel: MenuPanel
    private let metrics = MenuMetrics()
    private var outsideClicks: Any?
    private var visibility: NSKeyValueObservation?
    private var reasserted = false

    private let itemWidth: CGFloat = 24
    private let gap: CGFloat = 6
    private let screenInset: CGFloat = 8
    private let maxHeightFraction: CGFloat = 0.5

    init(appState: AppState) {
        self.appState = appState
        item = NSStatusBar.system.statusItem(withLength: 24)
        panel = MenuPanel(content: MenuBarRoot(appState: appState).environment(metrics))
        super.init()

        item.length = itemWidth
        item.behavior = []
        item.autosaveName = "Item-0"
        item.isVisible = true

        item.button?.target = self
        item.button?.action = #selector(toggle)

        renderGlyph()
        watchVisibility()
        Self.current = self
    }

    /// Redraws the icon whenever the state it reads changes. `withObservationTracking`
    /// is one-shot, so it re-arms itself after each change.
    private func renderGlyph() {
        withObservationTracking {
            item.button?.image = MenuBarGlyph.image(for: appState)
            item.button?.setAccessibilityLabel(MenuBarGlyph.accessibilityLabel(for: appState))
        } onChange: { [weak self] in
            Task { @MainActor in self?.renderGlyph() }
        }
    }

    func close() {
        panel.orderOut(nil)
        item.button?.isHighlighted = false
        stopWatchingOutsideClicks()
    }

    @objc private func toggle() {
        if panel.isVisible {
            close()
        } else {
            open()
        }
    }

    private func open() {
        guard let button = item.button, let bar = button.window else { return }
        let visible = (bar.screen ?? NSScreen.main)?.visibleFrame

        // The content asks for whatever height its list wants, so cap it and let the
        // list scroll inside that.
        metrics.heightBudget = (visible?.height ?? 800) * maxHeightFraction
        panel.layoutIfNeeded()
        panel.fitContent(maxHeight: metrics.heightBudget)
        let anchor = bar.convertToScreen(button.convert(button.bounds, to: nil))
        panel.setFrameOrigin(placement(under: anchor, within: visible))
        // A non-activating panel takes key input without pulling the app out of
        // .accessory, so opening the menu never steals focus from another app.
        panel.makeKeyAndOrderFront(nil)

        watchOutsideClicks()
        appState.refreshNow()
    }

    private func placement(under anchor: NSRect, within visible: NSRect?) -> NSPoint {
        let size = panel.frame.size
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - gap)

        guard let visible else { return origin }
        origin.x = min(max(visible.minX + screenInset, origin.x), visible.maxX - size.width - screenInset)
        origin.y = max(visible.minY + screenInset, origin.y)
        return origin
    }

    // MARK: - Dismissal

    /// A global monitor only sees events routed to *other* apps, so this closes the
    /// panel on an outside click while leaving clicks on our own icon to `toggle`.
    private func watchOutsideClicks() {
        guard outsideClicks == nil else { return }
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func stopWatchingOutsideClicks() {
        guard let outsideClicks else { return }
        NSEvent.removeMonitor(outsideClicks)
        self.outsideClicks = nil
    }

    // MARK: - Hidden icon

    /// Put the icon back once if the system hides it. If it is hidden again, say so
    /// instead of fighting for it - the app keeps running either way, and silently
    /// vanishing is what made this bug so expensive to find.
    private func watchVisibility() {
        visibility = item.observe(\.isVisible, options: [.new]) { [weak self] item, _ in
            MainActor.assumeIsolated {
                guard let self, !item.isVisible else { return }
                if self.reasserted {
                    NotificationManager.shared.sendMenuBarHiddenNotification()
                } else {
                    self.reasserted = true
                    item.isVisible = true
                }
            }
        }
    }
}

// MARK: - Panel

/// Borderless, non-activating window for the menu content. The content paints its
/// own glass chrome, so the window itself stays transparent.
private final class MenuPanel: NSPanel {
    private let hosting: NSViewController

    init<Content: View>(content: Content) {
        hosting = NSHostingController(rootView: content)
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 100, height: 100)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentViewController = hosting
        isFloatingPanel = true
        level = .popUpMenu
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    func fitContent(maxHeight: CGFloat) {
        var size = hosting.view.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        size.height = min(size.height, maxHeight)
        setContentSize(size)
    }
}
