import Foundation

// MARK: - Vercel Project Model

struct VercelProject: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let accountId: String?
    let framework: String?
    let createdAt: Int?
    let updatedAt: Int?
    
    var displayName: String {
        name
    }
}

// MARK: - Projects Response

struct VercelProjectsResponse: Codable {
    let projects: [VercelProject]
}
