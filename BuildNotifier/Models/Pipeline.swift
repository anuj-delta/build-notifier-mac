import Foundation

// MARK: - Workflow Details (CircleCI API v2)

struct WorkflowDetails: Codable {
    let id: String
    let name: String?
    let status: String?
    let pipelineId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case pipelineId = "pipeline_id"
    }
}

// MARK: - Pipeline Details (CircleCI API v2)

struct PipelineDetails: Codable {
    let id: String
    let state: String?
    let trigger: PipelineTrigger?
    let vcs: PipelineVCS?
}

struct PipelineTrigger: Codable {
    let type: String?
    let actor: PipelineActor?
    let receivedAt: String?

    enum CodingKeys: String, CodingKey {
        case type
        case actor
        case receivedAt = "received_at"
    }
}

struct PipelineActor: Codable {
    let login: String?
    let name: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case login
        case name
        case avatarUrl = "avatar_url"
    }
}

struct PipelineVCS: Codable {
    let branch: String?
}
