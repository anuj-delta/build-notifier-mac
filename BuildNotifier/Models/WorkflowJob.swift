import Foundation

// MARK: - Workflow Job Model (from CircleCI API v2)

struct WorkflowJob: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let projectSlug: String?
    let status: String
    let type: String?
    let approvedBy: String?
    let startedAt: String?
    let stoppedAt: String?
    let jobNumber: Int?
    
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
    
    var isApprovalJob: Bool {
        type == "approval"
    }
    
    var isPendingApproval: Bool {
        isApprovalJob && (status == "on_hold" || status == "blocked") && approvedBy == nil
    }
    
    var isApproved: Bool {
        isApprovalJob && approvedBy != nil
    }

    var canStillRequireApproval: Bool {
        guard isApprovalJob, approvedBy == nil else { return false }

        switch status {
        case "blocked", "on_hold", "not_run":
            return true
        default:
            return false
        }
    }

    var keepsWorkflowActionable: Bool {
        switch status {
        case "running", "queued", "blocked", "on_hold":
            return true
        default:
            return false
        }
    }
}

// MARK: - Workflow Jobs Response

struct WorkflowJobsResponse: Codable {
    let items: [WorkflowJob]
    let nextPageToken: String?
    
    enum CodingKeys: String, CodingKey {
        case items
        case nextPageToken = "next_page_token"
    }
}

// MARK: - Pending Approval

struct PendingApproval: Identifiable, Equatable {
    let id: String
    let workflowId: String
    let jobId: String
    let jobName: String
    let build: Build
    
    init(workflowId: String, job: WorkflowJob, build: Build) {
        self.id = "\(workflowId)-\(job.id)"
        self.workflowId = workflowId
        self.jobId = job.id
        self.jobName = job.name
        self.build = build
    }
    
    static func == (lhs: PendingApproval, rhs: PendingApproval) -> Bool {
        lhs.id == rhs.id
    }
}

struct ArmedAutoApproval: Identifiable, Equatable {
    let workflowId: String
    let buildId: String
    let buildNumber: Int
    let projectSlug: String
    let branch: String?
    let label: String
    let buildUrl: String?
    let armedAt: Date

    var id: String { workflowId }

    init?(build: Build, armedAt: Date = Date()) {
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
