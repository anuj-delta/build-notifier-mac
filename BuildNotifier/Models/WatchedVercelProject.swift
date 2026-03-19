import Foundation

// MARK: - Watched Vercel Project

struct WatchedVercelProject: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let teamId: String?
    let projectName: String
    var followMode: FollowMode
    var isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case teamId
        case projectName
        case followMode
        case isEnabled
    }

    init(from project: VercelProject, teamId: String?, followMode: FollowMode = .all) {
        self.id = project.id
        self.teamId = teamId
        self.projectName = project.name
        self.followMode = followMode
        self.isEnabled = true
    }

    init(id: String, teamId: String?, projectName: String, followMode: FollowMode = .all, isEnabled: Bool = true) {
        self.id = id
        self.teamId = teamId
        self.projectName = projectName
        self.followMode = followMode
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        teamId = try container.decodeIfPresent(String.self, forKey: .teamId)
        projectName = try container.decode(String.self, forKey: .projectName)
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
