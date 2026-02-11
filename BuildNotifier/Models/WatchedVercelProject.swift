import Foundation

// MARK: - Watched Vercel Project

struct WatchedVercelProject: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let teamId: String?
    let projectName: String
    var isEnabled: Bool
    
    init(from project: VercelProject, teamId: String?) {
        self.id = project.id
        self.teamId = teamId
        self.projectName = project.name
        self.isEnabled = true
    }
    
    init(id: String, teamId: String?, projectName: String, isEnabled: Bool = true) {
        self.id = id
        self.teamId = teamId
        self.projectName = projectName
        self.isEnabled = isEnabled
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
