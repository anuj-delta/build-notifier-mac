import Foundation

enum AppVersion {
    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}

struct ReleaseInfo: Equatable {
    let version: String
    let tagName: String
    let releaseURL: URL
    let downloadURL: URL?
}

actor UpdateChecker {
    static let shared = UpdateChecker()

    private let endpoint = URL(string: "https://api.github.com/repos/anuj-delta/build-notifier-mac/releases/latest")!

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlUrl: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: String
        }
    }

    /// Returns release info only when a newer version than `currentVersion` is published.
    func checkForUpdate(currentVersion: String = AppVersion.current) async -> ReleaseInfo? {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let release = try? decoder.decode(GitHubRelease.self, from: data),
              !release.draft, !release.prerelease else {
            return nil
        }

        let latest = normalizeVersion(release.tagName)
        guard isNewer(latest, than: normalizeVersion(currentVersion)) else { return nil }

        let dmg = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }

        return ReleaseInfo(
            version: latest,
            tagName: release.tagName,
            releaseURL: URL(string: release.htmlUrl) ?? endpoint,
            downloadURL: dmg.flatMap { URL(string: $0.browserDownloadUrl) }
        )
    }

    private func normalizeVersion(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: "v", with: "")
    }

    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(a.count, b.count)
        for i in 0..<count {
            let lhs = i < a.count ? a[i] : 0
            let rhs = i < b.count ? b[i] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }
}
