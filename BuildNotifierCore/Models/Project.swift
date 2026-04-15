import Foundation

// MARK: - Project Model (from CircleCI API v1.1)

public struct Project: Codable, Identifiable, Equatable {
    public let vcsUrl: String?
    public let followed: Bool?
    public let username: String
    public let reponame: String
    public let vcsType: String?
    public let branches: [String: BranchInfo]?
    
    public var id: String { slug }
    
    public var slug: String {
        "\(username)/\(reponame)"
    }
    
    public var vcsTypePrefix: String {
        guard let vcsUrl = vcsUrl else { return "gh" }
        if vcsUrl.contains("github.com") {
            return "gh"
        } else if vcsUrl.contains("bitbucket.org") {
            return "bb"
        }
        return "gh"
    }
    
    public var displayName: String {
        "\(username)/\(reponame)"
    }
    
    public var externalUrl: String {
        vcsUrl ?? "https://github.com/\(username)/\(reponame)"
    }

    public init(
        vcsUrl: String?,
        followed: Bool?,
        username: String,
        reponame: String,
        vcsType: String?,
        branches: [String: BranchInfo]?
    ) {
        self.vcsUrl = vcsUrl
        self.followed = followed
        self.username = username
        self.reponame = reponame
        self.vcsType = vcsType
        self.branches = branches
    }
    
    enum CodingKeys: String, CodingKey {
        case vcsUrl = "vcs_url"
        case followed
        case username
        case reponame
        case vcsType = "vcs_type"
        case branches
    }
    
    public static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.username == rhs.username && lhs.reponame == rhs.reponame
    }
}

public struct BranchInfo: Codable {
    public let pusherLogins: [String]?
    public let lastNonSuccess: LastBuildInfo?
    public let lastSuccess: LastBuildInfo?

    public init(pusherLogins: [String]?, lastNonSuccess: LastBuildInfo?, lastSuccess: LastBuildInfo?) {
        self.pusherLogins = pusherLogins
        self.lastNonSuccess = lastNonSuccess
        self.lastSuccess = lastSuccess
    }
    
    enum CodingKeys: String, CodingKey {
        case pusherLogins = "pusher_logins"
        case lastNonSuccess = "last_non_success"
        case lastSuccess = "last_success"
    }
}

public struct LastBuildInfo: Codable {
    public let pushedAt: String?
    public let vcsRevision: String?
    public let buildNum: Int?

    public init(pushedAt: String?, vcsRevision: String?, buildNum: Int?) {
        self.pushedAt = pushedAt
        self.vcsRevision = vcsRevision
        self.buildNum = buildNum
    }
    
    enum CodingKeys: String, CodingKey {
        case pushedAt = "pushed_at"
        case vcsRevision = "vcs_revision"
        case buildNum = "build_num"
    }
}

// MARK: - User Model (from /me endpoint)

public struct User: Codable {
    public let name: String?
    public let login: String?
    public let avatarUrl: String?
    public let selectedEmail: String?

    public init(name: String?, login: String?, avatarUrl: String?, selectedEmail: String?) {
        self.name = name
        self.login = login
        self.avatarUrl = avatarUrl
        self.selectedEmail = selectedEmail
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case login
        case avatarUrl = "avatar_url"
        case selectedEmail = "selected_email"
    }
}
