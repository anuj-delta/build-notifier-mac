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
    
    var id: String { "\(username ?? "")/\(reponame ?? "")/\(buildNum)" }
    
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
    
    static func == (lhs: Build, rhs: Build) -> Bool {
        lhs.buildNum == rhs.buildNum && 
        lhs.username == rhs.username && 
        lhs.reponame == rhs.reponame
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

    var autoApproveLabel: String {
        if let workflowName = workflows?.workflowName, !workflowName.isEmpty {
            return workflowName
        }
        if let jobName = workflows?.jobName, !jobName.isEmpty {
            return jobName
        }
        return "Build #\(buildNum)"
    }

    var relativeTime: String {
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
