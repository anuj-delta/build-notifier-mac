import Foundation

// MARK: - Vercel Deployment Model

struct VercelDeployment: Codable, Identifiable, Equatable {
    let uid: String
    let name: String
    let url: String?
    let state: String?
    let readyState: String?
    let createdAt: Int
    let buildingAt: Int?
    let ready: Int?
    let meta: VercelDeploymentMeta?
    let creator: VercelDeploymentCreator?
    let target: String?

    var id: String { uid }

    /// Vercel marks production deployments with `target == "production"`;
    /// preview deployments have `target == "preview"` or null.
    var isProduction: Bool { target == "production" }

    enum CodingKeys: String, CodingKey {
        case uid
        case name
        case url
        case state
        case readyState
        case createdAt
        case buildingAt
        case ready
        case meta
        case creator
        case target
    }
}

// MARK: - Deployment Meta

struct VercelDeploymentMeta: Codable, Equatable {
    let githubCommitRef: String?
    let githubCommitSha: String?
    let githubCommitMessage: String?
    let githubCommitAuthorName: String?
    let githubCommitAuthorLogin: String?
    let githubPrId: String?
    let gitBranch: String?
    let gitSha: String?
    
    var branch: String? {
        githubCommitRef ?? gitBranch
    }
    
    var commitSha: String? {
        let sha = githubCommitSha ?? gitSha
        return sha.map { String($0.prefix(7)) }
    }
    
    var prNumber: String? {
        githubPrId
    }
    
    var commitMessage: String? {
        githubCommitMessage
    }
    
    var authorName: String? {
        githubCommitAuthorName
    }
    
    var authorLogin: String? {
        githubCommitAuthorLogin
    }
}

// MARK: - Deployment Creator

struct VercelDeploymentCreator: Codable, Equatable {
    let uid: String?
    let username: String?
    let email: String?
}

// MARK: - Deployment Status

enum VercelDeploymentStatus: String {
    case building = "BUILDING"
    case queued = "QUEUED"
    case ready = "READY"
    case error = "ERROR"
    case canceled = "CANCELED"
    case initializing = "INITIALIZING"
    case unknown
    
    init(from state: String?) {
        if let state = state?.uppercased() {
            self = VercelDeploymentStatus(rawValue: state) ?? .unknown
        } else {
            self = .unknown
        }
    }
    
    var isSuccess: Bool {
        self == .ready
    }
    
    var isFailure: Bool {
        self == .error
    }
    
    var isRunning: Bool {
        self == .building || self == .queued || self == .initializing
    }
    
    var displayName: String {
        switch self {
        case .building: return "Building"
        case .queued: return "Queued"
        case .ready: return "Ready"
        case .error: return "Error"
        case .canceled: return "Canceled"
        case .initializing: return "Initializing"
        case .unknown: return "Unknown"
        }
    }
    
    var iconName: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .canceled: return "slash.circle.fill"
        case .building, .queued, .initializing: return "arrow.triangle.2.circlepath"
        case .unknown: return "questionmark.circle"
        }
    }
    
    var color: String {
        switch self {
        case .ready: return "green"
        case .error: return "red"
        case .canceled: return "gray"
        case .building, .queued, .initializing: return "yellow"
        case .unknown: return "gray"
        }
    }
}

// MARK: - Deployment Extensions

extension VercelDeployment {
    var deploymentStatus: VercelDeploymentStatus {
        VercelDeploymentStatus(from: readyState ?? state)
    }
    
    var projectName: String {
        name
    }
    
    var deploymentUrl: String? {
        if let url = url {
            return "https://\(url)"
        }
        return nil
    }
    
    var vercelDashboardUrl: String {
        "https://vercel.com/deployments/\(uid)"
    }

    /// Vercel's generated branch URL - `<project>-git-<branch>-<scope>.vercel.app` - which always serves the
    /// newest deployment on that branch, unlike `deploymentUrl` which is pinned to a single commit. Built
    /// locally rather than read from the alias API, because Vercel only assigns the branch alias to the
    /// newest deployment, so older rows would come back without it.
    func branchPreviewUrl(scopeSlug: String?) -> String? {
        guard !isProduction else { return nil }
        guard let scope = Self.urlSlug(scopeSlug ?? ""),
              let branch = Self.urlSlug(meta?.branch ?? ""),
              let project = Self.urlSlug(name) else { return nil }

        let host = "\(project)-git-\(branch)-\(scope)"
        // Past 63 characters Vercel truncates and appends its own hash, so the derived host stops matching.
        guard host.count <= 63 else { return nil }
        return "https://\(host).vercel.app"
    }

    static func urlSlug(_ value: String) -> String? {
        var slug = ""
        for character in value.lowercased() {
            if character.isASCII && (character.isLetter || character.isNumber) {
                slug.append(character)
            } else if !slug.isEmpty, slug.last != "-" {
                slug.append("-")
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? nil : slug
    }
    
    /// Human-readable commit author for notifications. Prefers the GitHub login (username).
    var authorDisplayName: String? {
        for candidate in [meta?.authorLogin, meta?.authorName] {
            if let name = candidate?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                return name
            }
        }
        return nil
    }

    var truncatedCommitMessage: String {
        guard let message = meta?.commitMessage else { return "No commit message" }
        let firstLine = message.components(separatedBy: .newlines).first ?? message
        if firstLine.count > 50 {
            return String(firstLine.prefix(47)) + "..."
        }
        return firstLine
    }
    
    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000)
    }
    
    var relativeTime: String {
        let now = Date()
        let interval = now.timeIntervalSince(createdDate)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Deployments Response

struct VercelDeploymentsResponse: Codable {
    let deployments: [VercelDeployment]
}
