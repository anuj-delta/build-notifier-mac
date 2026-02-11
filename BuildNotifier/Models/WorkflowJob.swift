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
