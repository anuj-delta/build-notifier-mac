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
    
    // Vercel settings
    var watchedVercelProjects: [WatchedVercelProject]
    var vercelNotificationsEnabled: Bool
    var notifyOnDeploymentReady: Bool
    var notifyOnDeploymentError: Bool
    var selectedVercelTeamId: String?
    
    static let `default` = UserPreferences(
        pollingIntervalSeconds: 60,
        launchAtLogin: false,
        notificationsEnabled: true,
        notificationSoundEnabled: true,
        notifyOnSuccess: true,
        notifyOnFailure: true,
        notifyOnPendingApproval: true,
        notifyOnBuildStarted: false,
        watchedProjects: [],
        watchedVercelProjects: [],
        vercelNotificationsEnabled: true,
        notifyOnDeploymentReady: true,
        notifyOnDeploymentError: true,
        selectedVercelTeamId: nil
    )
    
    // MARK: - Persistence
    
    private static let key = "UserPreferences"
    
    static func load() -> UserPreferences {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return .default
        }
        
        do {
            return try JSONDecoder().decode(UserPreferences.self, from: data)
        } catch {
            // Migration: decode partial data and fill in defaults for new fields
            if let partial = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var prefs = UserPreferences.default
                if let v = partial["pollingIntervalSeconds"] as? Int { prefs.pollingIntervalSeconds = v }
                if let v = partial["launchAtLogin"] as? Bool { prefs.launchAtLogin = v }
                if let v = partial["notificationsEnabled"] as? Bool { prefs.notificationsEnabled = v }
                if let v = partial["notificationSoundEnabled"] as? Bool { prefs.notificationSoundEnabled = v }
                if let v = partial["notifyOnSuccess"] as? Bool { prefs.notifyOnSuccess = v }
                if let v = partial["notifyOnFailure"] as? Bool { prefs.notifyOnFailure = v }
                if let v = partial["notifyOnPendingApproval"] as? Bool { prefs.notifyOnPendingApproval = v }
                if let v = partial["notifyOnBuildStarted"] as? Bool { prefs.notifyOnBuildStarted = v }
                if let watchedData = try? JSONSerialization.data(withJSONObject: partial["watchedProjects"] ?? []),
                   let watched = try? JSONDecoder().decode([WatchedProject].self, from: watchedData) {
                    prefs.watchedProjects = watched
                }
                if let v = partial["vercelNotificationsEnabled"] as? Bool { prefs.vercelNotificationsEnabled = v }
                if let v = partial["notifyOnDeploymentReady"] as? Bool { prefs.notifyOnDeploymentReady = v }
                if let v = partial["notifyOnDeploymentError"] as? Bool { prefs.notifyOnDeploymentError = v }
                if let vercelData = try? JSONSerialization.data(withJSONObject: partial["watchedVercelProjects"] ?? []),
                   let vercelWatched = try? JSONDecoder().decode([WatchedVercelProject].self, from: vercelData) {
                    prefs.watchedVercelProjects = vercelWatched
                }
                return prefs
            }
            return .default
        }
    }
    
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
