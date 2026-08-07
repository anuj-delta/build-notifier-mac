import AppKit

/// Opens links in whatever app owns them. Use this rather than `NSWorkspace.open(_:)`,
/// which waits on LaunchServices and so pins the caller through a cold browser launch.
enum ExternalLink {
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Tries each URL in turn and stops at the first one that opens.
    static func open(_ urls: [URL]) {
        guard let url = urls.first else { return }
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { app, _ in
            guard app == nil else { return }
            Task { @MainActor in open(Array(urls.dropFirst())) }
        }
    }
}
