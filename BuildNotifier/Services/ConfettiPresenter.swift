import AppKit
import SwiftUI

@MainActor
final class ConfettiPresenter {
    static let shared = ConfettiPresenter()

    private var panel: NSPanel?
    private let model = ConfettiOverlayModel()
    private var dismissTask: Task<Void, Never>?

    private let displayDuration: TimeInterval = 4.0
    private let exitDuration: TimeInterval = 0.5

    /// Shows the fullscreen confetti overlay. Repeated calls while it's already
    /// on screen coalesce into a single overlay listing every shipped project and
    /// reset the auto-dismiss timer, rather than stacking panels.
    func present(projectLabel: String, kind: CelebrationKind) {
        if panel == nil {
            model.reset()
        }
        model.isDismissing = false
        model.addProject(projectLabel)
        model.applyKind(kind)

        if panel == nil {
            showPanel()
        }
        scheduleDismiss()
    }

    private func showPanel() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }

        let panel = ConfettiPanel(contentRect: screen.frame)
        let host = NSHostingView(rootView: ConfettiOverlayView(model: model))
        host.frame = CGRect(origin: .zero, size: screen.frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.displayDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.model.isDismissing = true
            try? await Task.sleep(nanoseconds: UInt64(self.exitDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.close()
        }
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
        model.reset()
    }
}

private final class ConfettiPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        sharingType = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
