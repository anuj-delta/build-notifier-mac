import Foundation

extension Bundle {
    /// The processed SwiftPM resource bundle (celebration sounds, the PR-badge
    /// PDF, the asset catalog).
    ///
    /// An executable target's generated `Bundle.module` resolves only against
    /// `Bundle.main.bundleURL`, which in a packaged `.app` is the bundle root —
    /// a location that can't hold code-signed content. So the build ships the
    /// resource bundle inside `Contents/Resources` and we locate it via
    /// `resourceURL` (and the executable's own directory for `swift run`). We
    /// only reach for `Bundle.module` as a last resort, because merely reading
    /// it traps when the bundle isn't at the root.
    static let appResources: Bundle = {
        let name = "BuildNotifier_BuildNotifier.bundle"
        for base in [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap({ $0 }) {
            if let bundle = Bundle(url: base.appendingPathComponent(name)) {
                return bundle
            }
        }
        return .module
    }()
}
