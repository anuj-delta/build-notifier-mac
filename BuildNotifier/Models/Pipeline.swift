import Foundation

// MARK: - Workflow Details (CircleCI API v2)

struct WorkflowDetails: Codable {
    let id: String
    let name: String?
    let status: String?
    let pipelineId: String?
    /// Set once the workflow has terminated. CircleCI's rollup `status` can stay
    /// non-terminal (`running`/`failing`) after a rerun-from-failed even though the
    /// workflow has stopped, so `stoppedAt` is the reliable "it's done" signal.
    let stoppedAt: String?
    /// e.g. `rerun-workflow-from-failed` / `rerun-workflow-from-start`. Reruns are the
    /// case where the rollup stays non-terminal AND `stoppedAt` is never set, so `tag`
    /// is the only signal that a stuck-`running` workflow is actually a finished rerun.
    let tag: String?

    init(id: String, name: String?, status: String?, pipelineId: String?, stoppedAt: String? = nil, tag: String? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.pipelineId = pipelineId
        self.stoppedAt = stoppedAt
        self.tag = tag
    }

    /// A rerun whose rollup can be left stuck non-terminal by CircleCI.
    var isRerun: Bool { tag?.hasPrefix("rerun") ?? false }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case pipelineId = "pipeline_id"
        case stoppedAt = "stopped_at"
        case tag
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

// MARK: - Trigger Pipeline (CircleCI API v2)

struct TriggerPipelineRequest: Encodable {
    let branch: String
    let parameters: [String: String]?
}

struct TriggeredPipeline: Decodable {
    let id: String
    let number: Int
    let state: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case state
        case createdAt = "created_at"
    }
}
