import AppKit
import SwiftUI

/// How tall the menu is, and the most it may be on the screen it is opening on. The window
/// knows which screen it is on, the content does not, so the window sets these and the
/// content reads them. The height survives a relaunch, like any window frame.
@Observable
@MainActor
final class MenuMetrics {
    static let leastHeight: CGFloat = 280
    private static let defaultHeight: CGFloat = 560
    private static let key = "menuPanelHeight"

    private(set) var ceiling: CGFloat = MenuMetrics.defaultHeight
    private(set) var height: CGFloat

    init() {
        let saved = UserDefaults.standard.double(forKey: Self.key)
        height = saved > 0 ? saved : Self.defaultHeight
    }

    /// Fits the chosen height to the room under the menu bar on the screen being opened on.
    func fit(within room: CGFloat) {
        ceiling = max(Self.leastHeight, room)
        height = min(height, ceiling)
    }

    func resize(to height: CGFloat) {
        self.height = min(max(Self.leastHeight, height), ceiling)
    }

    func save() {
        UserDefaults.standard.set(height, forKey: Self.key)
    }
}

/// The menu bar icon and the panel it opens.
///
/// AppKit owns the status item rather than SwiftUI's `MenuBarExtra`, because that
/// API terminates the process when macOS asks the item to hide - exit code 0, no
/// crash log. Control Center hides an item whenever the app that launched it is
/// denied under "Allow in the Menu Bar", so a menu bar app must survive it.
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
    private var panelTop: CGFloat = 0

    private let itemWidth: CGFloat = 24
    private let gap: CGFloat = 6
    private let screenInset: CGFloat = 8

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
        trackHeight()
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
        let anchor = bar.convertToScreen(button.convert(button.bounds, to: nil))

        panelTop = anchor.minY - gap
        metrics.fit(within: panelTop - (visible?.minY ?? 0) - screenInset)
        panel.layoutIfNeeded()
        panel.fitContent()
        panel.setFrameOrigin(placement(under: anchor, within: visible))
        // A non-activating panel takes key input without pulling the app out of
        // .accessory, so opening the menu never steals focus from another app.
        panel.makeKeyAndOrderFront(nil)

        watchOutsideClicks()
        appState.refreshNow()
    }

    /// Hangs the panel from the icon's leading edge, the way macOS drops its own menus, and
    /// keeps it on screen. Centring on the icon reads as misaligned once the panel is much
    /// wider than the icon.
    private func placement(under anchor: NSRect, within visible: NSRect?) -> NSPoint {
        let size = panel.frame.size
        var origin = NSPoint(x: anchor.minX, y: panelTop - size.height)

        guard let visible else { return origin }
        origin.x = min(max(visible.minX + screenInset, origin.x), visible.maxX - size.width - screenInset)
        origin.y = max(visible.minY + screenInset, origin.y)
        return origin
    }

    /// Follows the height the resize handle writes, keeping the top edge pinned under the icon
    /// so the panel grows downward. `withObservationTracking` is one-shot, so it re-arms.
    private func trackHeight() {
        withObservationTracking {
            _ = metrics.height
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyHeight()
                self?.trackHeight()
            }
        }
    }

    private func applyHeight() {
        guard panel.isVisible else { return }
        panel.setContentSize(NSSize(width: panel.frame.width, height: metrics.height))
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: panelTop - panel.frame.height))
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

    func fitContent() {
        let size = hosting.view.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        setContentSize(size)
    }
}
