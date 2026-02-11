import Foundation

// MARK: - Follow Mode

enum FollowMode: String, Codable, CaseIterable {
    case all = "all"
    case mine = "mine"
    
    var displayName: String {
        switch self {
        case .all: return "All builds"
        case .mine: return "My builds only"
        }
    }
}

// MARK: - Watched Project

struct WatchedProject: Codable, Identifiable, Equatable, Hashable {
    let id: String  // "gh/org/repo" format
    let vcsType: String
    let orgName: String
    let repoName: String
    var followMode: FollowMode
    var isEnabled: Bool
    
    init(from project: Project, followMode: FollowMode = .all) {
        self.id = "\(project.vcsTypePrefix)/\(project.username)/\(project.reponame)"
        self.vcsType = project.vcsTypePrefix
        self.orgName = project.username
        self.repoName = project.reponame
        self.followMode = followMode
        self.isEnabled = true
    }
    
    init(id: String, vcsType: String, orgName: String, repoName: String, followMode: FollowMode = .all, isEnabled: Bool = true) {
        self.id = id
        self.vcsType = vcsType
        self.orgName = orgName
        self.repoName = repoName
        self.followMode = followMode
        self.isEnabled = isEnabled
    }
    
    var displayName: String {
        "\(orgName)/\(repoName)"
    }
    
    var slug: String {
        "\(orgName)/\(repoName)"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: WatchedProject, rhs: WatchedProject) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - User Preferences

struct UserPreferences: Codable {
    var pollingIntervalSeconds: Int
    var launchAtLogin: Bool  // Start on startup
    var notificationsEnabled: Bool  // Global toggle
    var notificationSoundEnabled: Bool  // Sound toggle
    var notifyOnSuccess: Bool
    var notifyOnFailure: Bool
    var notifyOnPendingApproval: Bool
    var notifyOnBuildStarted: Bool
    var watchedProjects: [WatchedProject]
    
    static let `default` = UserPreferences(
        pollingIntervalSeconds: 60,
        launchAtLogin: false,
        notificationsEnabled: true,
        notificationSoundEnabled: true,
        notifyOnSuccess: true,
        notifyOnFailure: true,
        notifyOnPendingApproval: true,
        notifyOnBuildStarted: false,
        watchedProjects: []
    )
    
    // MARK: - Persistence
    
    private static let key = "UserPreferences"
    
    static func load() -> UserPreferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let preferences = try? JSONDecoder().decode(UserPreferences.self, from: data) else {
            return .default
        }
        return preferences
    }
    
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
