import Foundation

/// Decides whether a branch name counts as "production" for the confetti feature.
/// Patterns are matched case-insensitively and support a single `*` wildcard that
/// matches any run of characters (e.g. `release/*`, `*-prod`).
enum ProductionBranchMatcher {
    static func isProduction(branch: String?, patterns: [String]) -> Bool {
        guard let branch = branch?.trimmingCharacters(in: .whitespacesAndNewlines),
              !branch.isEmpty else { return false }
        let candidate = branch.lowercased()
        return patterns.contains { matches(candidate, pattern: $0) }
    }

    private static func matches(_ candidate: String, pattern rawPattern: String) -> Bool {
        let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !pattern.isEmpty else { return false }

        guard let starIndex = pattern.firstIndex(of: "*") else {
            return candidate == pattern
        }

        let prefix = pattern[pattern.startIndex..<starIndex]
        let suffix = pattern[pattern.index(after: starIndex)...]

        guard candidate.count >= prefix.count + suffix.count else { return false }
        return candidate.hasPrefix(prefix) && candidate.hasSuffix(suffix)
    }
}
