import Foundation

// MARK: - Build Model (from CircleCI API v1.1)

public struct Build: Codable, Identifiable, Equatable {
    public let vcsUrl: String?
    public let buildUrl: String?
    public let buildNum: Int
    public let branch: String?
    public let vcsRevision: String?
    public let committerName: String?
    public let committerEmail: String?
    public let subject: String?
    public let body: String?
    public let why: String?
    public let queuedAt: String?
    public let startTime: String?
    public let stopTime: String?
    public let buildTimeMillis: Int?
    public let username: String?
    public let reponame: String?
    public let lifecycle: String?
    public let outcome: String?
    public let status: String?
    public let retryOf: Int?
    public let workflows: WorkflowInfo?
    
    public var id: String { "\(username ?? "")/\(reponame ?? "")/\(buildNum)" }

    public init(
        vcsUrl: String?,
        buildUrl: String?,
        buildNum: Int,
        branch: String?,
        vcsRevision: String?,
        committerName: String?,
        committerEmail: String?,
        subject: String?,
        body: String?,
        why: String?,
        queuedAt: String?,
        startTime: String?,
        stopTime: String?,
        buildTimeMillis: Int?,
        username: String?,
        reponame: String?,
        lifecycle: String?,
        outcome: String?,
        status: String?,
        retryOf: Int?,
        workflows: WorkflowInfo?
    ) {
        self.vcsUrl = vcsUrl
        self.buildUrl = buildUrl
        self.buildNum = buildNum
        self.branch = branch
        self.vcsRevision = vcsRevision
        self.committerName = committerName
        self.committerEmail = committerEmail
        self.subject = subject
        self.body = body
        self.why = why
        self.queuedAt = queuedAt
        self.startTime = startTime
        self.stopTime = stopTime
        self.buildTimeMillis = buildTimeMillis
        self.username = username
        self.reponame = reponame
        self.lifecycle = lifecycle
        self.outcome = outcome
        self.status = status
        self.retryOf = retryOf
        self.workflows = workflows
    }
    
    enum CodingKeys: String, CodingKey {
        case vcsUrl = "vcs_url"
        case buildUrl = "build_url"
        case buildNum = "build_num"
        case branch
        case vcsRevision = "vcs_revision"
        case committerName = "committer_name"
        case committerEmail = "committer_email"
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
    }
    
    public static func == (lhs: Build, rhs: Build) -> Bool {
        lhs.buildNum == rhs.buildNum && 
        lhs.username == rhs.username && 
        lhs.reponame == rhs.reponame
    }
}

public struct WorkflowInfo: Codable, Equatable {
    public let jobName: String?
    public let workflowId: String?
    public let workflowName: String?

    public init(jobName: String?, workflowId: String?, workflowName: String?) {
        self.jobName = jobName
        self.workflowId = workflowId
        self.workflowName = workflowName
    }
    
    enum CodingKeys: String, CodingKey {
        case jobName = "job_name"
        case workflowId = "workflow_id"
        case workflowName = "workflow_name"
    }
}

// MARK: - Build Status

public enum BuildStatus: String {
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
    
    public init(from status: String?) {
        self = BuildStatus(rawValue: Self.normalize(status)) ?? .unknown
    }
    
    public init(status: String?, outcome: String?, lifecycle: String?) {
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
    
    public var isSuccess: Bool {
        self == .success || self == .fixed
    }
    
    public var isFailure: Bool {
        self == .failed || self == .timedout || self == .infrastructureFail
    }
    
    public var isRunning: Bool {
        self == .running || self == .queued || self == .scheduled || self == .notRunning
    }
    
    public var isPending: Bool {
        self == .onHold
    }

    public var isTerminal: Bool {
        switch self {
        case .success, .fixed, .failed, .timedout, .infrastructureFail, .canceled, .retried, .noTests:
            return true
        default:
            return false
        }
    }
    
    public var displayName: String {
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
    
    public var iconName: String {
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
    
    public var color: String {
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
    public var projectOrganizationName: String? {
        username
    }

    public var projectRepositoryName: String {
        reponame ?? "unknown"
    }

    public var buildStatus: BuildStatus {
        BuildStatus(status: status, outcome: outcome, lifecycle: lifecycle)
    }
    
    public var projectSlug: String {
        guard let username = username, let reponame = reponame else {
            return "unknown"
        }
        return "\(username)/\(reponame)"
    }
    
    public var vcsType: String {
        guard let vcsUrl = vcsUrl else { return "gh" }
        if vcsUrl.contains("github.com") {
            return "gh"
        } else if vcsUrl.contains("bitbucket.org") {
            return "bb"
        }
        return "gh"
    }
    
    public var truncatedSubject: String {
        guard let subject = subject else { return "No commit message" }
        if subject.count > 50 {
            return String(subject.prefix(47)) + "..."
        }
        return subject
    }
    
    /// Best-effort timestamp for sorting projects by activity.
    /// Prefers `start_time`, then `queued_at`, then `stop_time`.
    public var activityDate: Date? {
        if let startTime { return Self.parseISO8601(startTime) }
        if let queuedAt { return Self.parseISO8601(queuedAt) }
        if let stopTime { return Self.parseISO8601(stopTime) }
        return nil
    }
    
    public var workflowUrl: String? {
        guard let workflowId = workflows?.workflowId else { return nil }
        return "https://app.circleci.com/pipelines/workflows/\(workflowId)"
    }

    public var autoApproveLabel: String {
        if let workflowName = workflows?.workflowName, !workflowName.isEmpty {
            return workflowName
        }
        if let jobName = workflows?.jobName, !jobName.isEmpty {
            return jobName
        }
        return "Build #\(buildNum)"
    }

    public var relativeTime: String {
        guard let buildDate = activityDate else {
            return "unknown"
        }
        
        let now = Date()
        let interval = now.timeIntervalSince(buildDate)
        
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
    
    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
