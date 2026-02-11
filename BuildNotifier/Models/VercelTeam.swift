import Foundation

// MARK: - Vercel Team Model

struct VercelTeam: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let slug: String
    
    var displayName: String {
        name.isEmpty ? slug : name
    }
}

// MARK: - Teams Response

struct VercelTeamsResponse: Codable {
    let teams: [VercelTeam]
}
