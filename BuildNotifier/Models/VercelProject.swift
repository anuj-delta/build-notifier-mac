import Foundation

// MARK: - Vercel Project Model

struct VercelProject: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let accountId: String?
    let framework: String?
    let createdAt: Int?
    let updatedAt: Int?
    let link: VercelProjectLink?

    var displayName: String {
        name
    }

    /// The repository this project deploys, in `WatchedProject.slug` form, for the projects
    /// connected to a GitHub repo. CLI-deployed projects have no link and group on their own.
    var repoSlug: String? {
        link?.repoSlug
    }
}

/// The git repository a Vercel project deploys from. Only the GitHub shape is decoded; GitLab
/// names the same fields differently and nothing in the app reads it.
struct VercelProjectLink: Codable, Equatable, Hashable {
    let type: String?
    let org: String?
    let repo: String?
    let productionBranch: String?

    var repoSlug: String? {
        guard type == "github", let org, let repo else { return nil }
        return "\(org)/\(repo)".lowercased()
    }
}

// MARK: - Projects Response

struct VercelProjectsResponse: Codable {
    let projects: [VercelProject]
}
