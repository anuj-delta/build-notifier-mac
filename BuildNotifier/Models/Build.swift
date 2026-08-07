import Foundation

// MARK: - Build Model (from CircleCI API v1.1)

struct Build: Codable, Identifiable, Equatable {
    let vcsUrl: String?
    let buildUrl: String?
    let buildNum: Int
    let branch: String?
    let vcsRevision: String?
    let committerName: String?
    let committerEmail: String?
    let authorName: String?
    let authorEmail: String?
    let subject: String?
    let body: String?
    let why: String?
    let queuedAt: String?
    let startTime: String?
    let stopTime: String?
    let buildTimeMillis: Int?
    let username: String?
    let reponame: String?
    let lifecycle: String?
    let outcome: String?
    let status: String?
    let retryOf: Int?
    let workflows: WorkflowInfo?
    let pullRequests: [PullRequest]?

    var id: String { "\(username ?? "")/\(reponame ?? "")/\(buildNum)" }

    enum CodingKeys: String, CodingKey {
        case vcsUrl = "vcs_url"
        case buildUrl = "build_url"
        case buildNum = "build_num"
        case branch
        case vcsRevision = "vcs_revision"
        case committerName = "committer_name"
        case committerEmail = "committer_email"
        case authorName = "author_name"
        case authorEmail = "author_email"
        case subject
        case body
        case why
        case queuedAt = "queued_at"
        case startTime = "start_time"
        case stopTime = "stop_time"
        case buildTimeMillis = "build_time_millis"
        case username
        case reponame
        case lifecycle
        case outcome
        case status
        case retryOf = "retry_of"
        case workflows
        case pullRequests = "pull_requests"
    }
    
    static func == (lhs: Build, rhs: Build) -> Bool {
        lhs.buildNum == rhs.buildNum && 
        lhs.username == rhs.username && 
        lhs.reponame == rhs.reponame
    }
}

struct PullRequest: Codable, Equatable {
    let headSha: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case headSha = "head_sha"
        case url
    }
}

struct WorkflowInfo: Codable, Equatable {
    let jobName: String?
    let workflowId: String?
    let workflowName: String?
    
    enum CodingKeys: String, CodingKey {
        case jobName = "job_name"
        case workflowId = "workflow_id"
        case workflowName = "workflow_name"
    }
}

// MARK: - Build Status

enum BuildStatus: String {
    case success
    case fixed
    case failed
    case timedout
    case infrastructureFail = "infrastructure_fail"
    case canceled
    case running
    case notRun = "not_run"
    case notRunning = "not_running"
    case queued
    case scheduled
    case retried
    case noTests = "no_tests"
    case onHold = "on_hold"
    case unknown
    
    init(from status: String?) {
        self = BuildStatus(rawValue: Self.normalize(status)) ?? .unknown
    }
    
    init(status: String?, outcome: String?, lifecycle: String?) {
        let normalizedOutcome = Self.normalize(outcome)
        let normalizedLifecycle = Self.normalize(lifecycle)
        let normalizedStatus = Self.normalize(status)
        
        if normalizedOutcome == "canceled" || normalizedLifecycle == "canceled" {
            self = .canceled
            return
        }
        
        if let outcomeStatus = BuildStatus(rawValue: normalizedOutcome), outcomeStatus != .unknown {
            self = outcomeStatus
            return
        }
        
        self = BuildStatus(rawValue: normalizedStatus) ?? .unknown
    }
    
    private static func normalize(_ value: String?) -> String {
        (value ?? "").lowercased().replacingOccurrences(of: "cancelled", with: "canceled")
    }
    
    var isSuccess: Bool {
        self == .success || self == .fixed
    }
    
    var isFailure: Bool {
        self == .failed || self == .timedout || self == .infrastructureFail
    }
    
    var isRunning: Bool {
        self == .running || self == .queued || self == .scheduled || self == .notRunning
    }
    
    var isPending: Bool {
        self == .onHold
    }

    var isTerminal: Bool {
        switch self {
        case .success, .fixed, .failed, .timedout, .infrastructureFail, .canceled, .retried, .noTests:
            return true
        default:
            return false
        }
    }
    
    var displayName: String {
        switch self {
        case .success: return "Success"
        case .fixed: return "Fixed"
        case .failed: return "Failed"
        case .timedout: return "Timed Out"
        case .infrastructureFail: return "Infra Fail"
        case .canceled: return "Canceled"
        case .running: return "Running"
        case .notRun: return "Not Run"
        case .notRunning: return "Pending"
        case .queued: return "Queued"
        case .scheduled: return "Scheduled"
        case .retried: return "Retried"
        case .noTests: return "No Tests"
        case .onHold: return "On Hold"
        case .unknown: return "Unknown"
        }
    }
    
    var iconName: String {
        switch self {
        case .success, .fixed: return "checkmark.circle.fill"
        case .failed, .timedout, .infrastructureFail: return "xmark.circle.fill"
        case .canceled: return "slash.circle.fill"
        case .running, .notRunning: return "arrow.triangle.2.circlepath"
        case .queued, .scheduled: return "clock.fill"
        case .onHold: return "pause.circle.fill"
        default: return "questionmark.circle"
        }
    }
    
    var color: String {
        switch self {
        case .success, .fixed: return "green"
        case .failed, .timedout, .infrastructureFail: return "red"
        case .canceled: return "gray"
        case .running, .notRunning, .queued, .scheduled: return "yellow"
        case .onHold: return "orange"
        default: return "gray"
        }
    }
}

// MARK: - Build Extensions

extension Build {
    var projectOrganizationName: String? {
        username
    }

    var projectRepositoryName: String {
        reponame ?? "unknown"
    }

    var buildStatus: BuildStatus {
        BuildStatus(status: status, outcome: outcome, lifecycle: lifecycle)
    }
    
    var projectSlug: String {
        guard let username = username, let reponame = reponame else {
            return "unknown"
        }
        return "\(username)/\(reponame)"
    }
    
    var vcsType: String {
        guard let vcsUrl = vcsUrl else { return "gh" }
        if vcsUrl.contains("github.com") {
            return "gh"
        } else if vcsUrl.contains("bitbucket.org") {
            return "bb"
        }
        return "gh"
    }
    
    /// Human-readable commit author for notifications. Prefers author over committer,
    /// then falls back to the local-part of whichever email is present.
    var authorDisplayName: String? {
        for candidate in [authorName, committerName] {
            if let name = candidate?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                return name
            }
        }
        for email in [authorEmail, committerEmail] {
            if let local = email?.split(separator: "@").first, !local.isEmpty {
                return String(local)
            }
        }
        return nil
    }

    var truncatedSubject: String {
        guard let subject = subject else { return "No commit message" }
        if subject.count > 50 {
            return String(subject.prefix(47)) + "..."
        }
        return subject
    }
    
    /// Best-effort timestamp for sorting projects by activity.
    /// Prefers `start_time`, then `queued_at`, then `stop_time`.
    var activityDate: Date? {
        if let startTime { return Self.parseISO8601(startTime) }
        if let queuedAt { return Self.parseISO8601(queuedAt) }
        if let stopTime { return Self.parseISO8601(stopTime) }
        return nil
    }
    
    var workflowUrl: String? {
        guard let workflowId = workflows?.workflowId else { return nil }
        return "https://app.circleci.com/pipelines/workflows/\(workflowId)"
    }

    var pullRequestUrl: String? {
        guard let url = pullRequests?.first?.url, !url.isEmpty else { return nil }
        return url
    }

    /// PR number parsed from the trailing path segment of the PR URL (e.g. `.../pull/478` -> 478).
    var pullRequestNumber: Int? {
        guard let last = pullRequestUrl?.split(separator: "/").last else { return nil }
        return Int(last)
    }

    var autoApproveLabel: String {
        if let workflowName = workflows?.workflowName, !workflowName.isEmpty {
            return workflowName
        }
        if let jobName = workflows?.jobName, !jobName.isEmpty {
            return jobName
        }
        return "Build #\(buildNum)"
    }

    var startedDate: Date? {
        guard let startTime else { return nil }
        return Self.parseISO8601(startTime)
    }

    var stoppedDate: Date? {
        guard let stopTime else { return nil }
        return Self.parseISO8601(stopTime)
    }

    // Sort comparators parse dates thousands of times per redraw, and allocating a
    // formatter per call dominated the cost.
    private static let fractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let wholeSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func parseISO8601(_ value: String) -> Date? {
        fractionalSecondsFormatter.date(from: value) ?? wholeSecondsFormatter.date(from: value)
    }
}
