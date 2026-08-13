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
        let text = commitSubject
        if text.count > 50 {
            return String(text.prefix(47)) + "..."
        }
        return text
    }
    
    /// Best-effort timestamp for sorting projects by activity.
    /// Prefers `start_time`, then `queued_at`, then `stop_time`.
    var activityDate: Date? {
        if let startTime { return Self.parseISO8601(startTime) }
        if let queuedAt { return Self.parseISO8601(queuedAt) }
        if let stopTime { return Self.parseISO8601(stopTime) }
        return nil
    }
    
    /// When the build reached the state a notification would be about. `activityDate`
    /// prefers `start_time`, which for a long build that just passed is an hour stale.
    var stateChangeDate: Date? {
        if buildStatus.isTerminal, let stopTime {
            return Self.parseISO8601(stopTime)
        }
        return activityDate
    }

    var workflowUrl: String? {
        guard let workflowId = workflows?.workflowId else { return nil }
        return "https://app.circleci.com/pipelines/workflows/\(workflowId)"
    }

    /// Falls back to the PR named in a merge commit, so a build on a long-lived branch like
    /// `main` still links to the PR that landed on it after that PR closed.
    var pullRequestUrl: String? {
        if let url = pullRequests?.first?.url, !url.isEmpty {
            return url
        }
        guard vcsType == "gh",
              let repoUrl = vcsUrl?.trimmingCharacters(in: CharacterSet(charactersIn: "/")), !repoUrl.isEmpty,
              let number = mergedPullRequestNumber else {
            return nil
        }
        return "\(repoUrl)/pull/\(number)"
    }

    /// PR number in a merge commit subject: GitHub's `Merge pull request #281 from org/branch`,
    /// or a squash merge's `Some title (#281)`.
    private var mergedPullRequestNumber: Int? {
        guard let subject else { return nil }
        if let match = subject.firstMatch(of: Self.mergePrefix) { return Int(match.1) }
        if let match = subject.firstMatch(of: Self.squashSuffix) { return Int(match.1) }
        return nil
    }

    /// The PR title, when the commit carries one. GitHub puts it in the body of a merge commit,
    /// and in front of the number on a squash merge. A plain commit has no PR title: its body is
    /// the long message, not a title.
    var pullRequestTitle: String? {
        guard let subject else { return nil }
        guard subject.starts(with: Self.mergePrefix) else { return squashTitle }
        let title = body?
            .split(separator: "\n").first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return title.isEmpty ? nil : title
    }

    /// The commit subject, without the `into <branch>` tail that only names this build's branch.
    var commitSubject: String {
        guard let subject = subject?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty else {
            return "No commit message"
        }
        guard let branch, subject.hasSuffix(" into \(branch)") else { return subject }
        return String(subject.dropLast(" into \(branch)".count))
    }

    /// The subject for a build row, which shows the PR number in its own badge.
    var rowSubject: String {
        squashTitle ?? commitSubject
    }

    /// The commit author, or nil when the signed-in user made the commit. Their own name sits on
    /// almost every row, and the row gives that width to the PR title instead.
    func authorDisplayName(excluding user: User?) -> String? {
        guard let author = authorDisplayName else { return nil }
        guard let user else { return author }
        let mine = user.identities
        if mine.contains(author.lowercased()) { return nil }
        if let email = authorEmail?.lowercased(), mine.contains(email) { return nil }
        return author
    }

    /// The text in front of a squash merge's `(#281)`.
    private var squashTitle: String? {
        guard let subject, let match = subject.firstMatch(of: Self.squashSuffix) else { return nil }
        let title = subject[subject.startIndex..<match.range.lowerBound]
            .trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    private static let mergePrefix = #/^Merge pull request #(\d+)/#
    private static let squashSuffix = #/\s*\(#(\d+)\)\s*$/#

    /// The PR number from the API's URL (e.g. `.../pull/478`), or from the merge commit.
    var pullRequestNumber: Int? {
        if let url = pullRequests?.first?.url,
           let last = url.split(separator: "/").last,
           let number = Int(last) {
            return number
        }
        return mergedPullRequestNumber
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
