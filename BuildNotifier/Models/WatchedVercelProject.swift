import Foundation

// MARK: - Watched Vercel Project

struct WatchedVercelProject: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let teamId: String?
    let projectName: String
    /// Team slug (or personal account username), the scope segment of Vercel's generated branch URLs.
    /// The deployments API never returns it, so it is captured when the project is added.
    var teamSlug: String?
    /// The repository this project deploys, as `org/repo` lowercased, so its deployments merge
    /// into the same card as the repository's CircleCI builds. Detected from the project's git
    /// link, and overridable in Settings for the projects Vercel reports no link for.
    var repoSlug: String?
    var followMode: FollowMode
    var isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case teamId
        case projectName
        case teamSlug
        case repoSlug
        case followMode
        case isEnabled
    }

    init(
        from project: VercelProject,
        teamId: String?,
        teamSlug: String? = nil,
        followMode: FollowMode = .all
    ) {
        self.id = project.id
        self.teamId = teamId
        self.projectName = project.name
        self.teamSlug = teamSlug
        self.repoSlug = project.repoSlug
        self.followMode = followMode
        self.isEnabled = true
    }

    init(
        id: String,
        teamId: String?,
        projectName: String,
        teamSlug: String? = nil,
        repoSlug: String? = nil,
        followMode: FollowMode = .all,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.teamId = teamId
        self.projectName = projectName
        self.teamSlug = teamSlug
        self.repoSlug = repoSlug
        self.followMode = followMode
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        teamId = try container.decodeIfPresent(String.self, forKey: .teamId)
        projectName = try container.decode(String.self, forKey: .projectName)
        teamSlug = try container.decodeIfPresent(String.self, forKey: .teamSlug)
        repoSlug = try container.decodeIfPresent(String.self, forKey: .repoSlug)
        followMode = try container.decodeIfPresent(FollowMode.self, forKey: .followMode) ?? .all
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
    
    var displayName: String {
        projectName
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: WatchedVercelProject, rhs: WatchedVercelProject) -> Bool {
        lhs.id == rhs.id
    }
}
