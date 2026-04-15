import Foundation

// MARK: - Workflow Job Model (from CircleCI API v2)

public struct WorkflowJob: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let projectSlug: String?
    public let status: String
    public let type: String?
    public let approvedBy: String?
    public let startedAt: String?
    public let stoppedAt: String?
    public let jobNumber: Int?

    public init(
        id: String,
        name: String,
        projectSlug: String?,
        status: String,
        type: String?,
        approvedBy: String?,
        startedAt: String?,
        stoppedAt: String?,
        jobNumber: Int?
    ) {
        self.id = id
        self.name = name
        self.projectSlug = projectSlug
        self.status = status
        self.type = type
        self.approvedBy = approvedBy
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
        self.jobNumber = jobNumber
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case projectSlug = "project_slug"
        case status
        case type
        case approvedBy = "approved_by"
        case startedAt = "started_at"
        case stoppedAt = "stopped_at"
        case jobNumber = "job_number"
    }
    
    public var isApprovalJob: Bool {
        type == "approval"
    }
    
    public var isPendingApproval: Bool {
        isApprovalJob && (status == "on_hold" || status == "blocked") && approvedBy == nil
    }
    
    public var isApproved: Bool {
        isApprovalJob && approvedBy != nil
    }

    public var canStillRequireApproval: Bool {
        guard isApprovalJob, approvedBy == nil else { return false }

        switch status {
        case "blocked", "on_hold", "not_run":
            return true
        default:
            return false
        }
    }

    public var keepsWorkflowActionable: Bool {
        switch status {
        case "running", "queued", "blocked", "on_hold":
            return true
        default:
            return false
        }
    }
}

// MARK: - Workflow Jobs Response

public struct WorkflowJobsResponse: Codable {
    public let items: [WorkflowJob]
    public let nextPageToken: String?

    public init(items: [WorkflowJob], nextPageToken: String?) {
        self.items = items
        self.nextPageToken = nextPageToken
    }
    
    enum CodingKeys: String, CodingKey {
        case items
        case nextPageToken = "next_page_token"
    }
}

// MARK: - Pending Approval

public struct PendingApproval: Identifiable, Equatable {
    public let id: String
    public let workflowId: String
    public let jobId: String
    public let jobName: String
    public let build: Build
    
    public init(workflowId: String, job: WorkflowJob, build: Build) {
        self.id = "\(workflowId)-\(job.id)"
        self.workflowId = workflowId
        self.jobId = job.id
        self.jobName = job.name
        self.build = build
    }
    
    public static func == (lhs: PendingApproval, rhs: PendingApproval) -> Bool {
        lhs.id == rhs.id
    }
}

public struct ArmedAutoApproval: Identifiable, Equatable {
    public let workflowId: String
    public let buildId: String
    public let buildNumber: Int
    public let projectSlug: String
    public let branch: String?
    public let label: String
    public let buildUrl: String?
    public let armedAt: Date

    public var id: String { workflowId }

    public init?(build: Build, armedAt: Date = Date()) {
        guard let workflowId = build.workflows?.workflowId else { return nil }

        self.workflowId = workflowId
        self.buildId = build.id
        self.buildNumber = build.buildNum
        self.projectSlug = build.projectSlug
        self.branch = build.branch
        self.label = build.autoApproveLabel
        self.buildUrl = build.workflowUrl ?? build.buildUrl
        self.armedAt = armedAt
    }
}
