import Foundation

// MARK: - Project Model (from CircleCI API v1.1)

struct Project: Codable, Identifiable, Equatable {
    let vcsUrl: String?
    let followed: Bool?
    let username: String
    let reponame: String
    let vcsType: String?
    let branches: [String: BranchInfo]?
    
    var id: String { slug }
    
    var slug: String {
        "\(username)/\(reponame)"
    }
    
    var vcsTypePrefix: String {
        guard let vcsUrl = vcsUrl else { return "gh" }
        if vcsUrl.contains("github.com") {
            return "gh"
        } else if vcsUrl.contains("bitbucket.org") {
            return "bb"
        }
        return "gh"
    }
    
    var displayName: String {
        "\(username)/\(reponame)"
    }
    
    var externalUrl: String {
        vcsUrl ?? "https://github.com/\(username)/\(reponame)"
    }
    
    enum CodingKeys: String, CodingKey {
        case vcsUrl = "vcs_url"
        case followed
        case username
        case reponame
        case vcsType = "vcs_type"
        case branches
    }
    
    static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.username == rhs.username && lhs.reponame == rhs.reponame
    }
}

struct BranchInfo: Codable {
    let pusherLogins: [String]?
    let lastNonSuccess: LastBuildInfo?
    let lastSuccess: LastBuildInfo?
    
    enum CodingKeys: String, CodingKey {
        case pusherLogins = "pusher_logins"
        case lastNonSuccess = "last_non_success"
        case lastSuccess = "last_success"
    }
}

struct LastBuildInfo: Codable {
    let pushedAt: String?
    let vcsRevision: String?
    let buildNum: Int?
    
    enum CodingKeys: String, CodingKey {
        case pushedAt = "pushed_at"
        case vcsRevision = "vcs_revision"
        case buildNum = "build_num"
    }
}

// MARK: - User Model (from /me endpoint)

struct User: Codable {
    let name: String?
    let login: String?
    let avatarUrl: String?
    let selectedEmail: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case login
        case avatarUrl = "avatar_url"
        case selectedEmail = "selected_email"
    }

    /// The handles a commit can carry for this user, lowercased for comparison.
    var identities: Set<String> {
        Set([name, login, selectedEmail].compactMap { $0?.lowercased() })
    }
}
