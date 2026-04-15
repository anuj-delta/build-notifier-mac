import Foundation

// MARK: - Workflow Details (CircleCI API v2)

public struct WorkflowDetails: Codable {
    public let id: String
    public let name: String?
    public let status: String?
    public let pipelineId: String?

    public init(id: String, name: String?, status: String?, pipelineId: String?) {
        self.id = id
        self.name = name
        self.status = status
        self.pipelineId = pipelineId
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case pipelineId = "pipeline_id"
    }
}

// MARK: - Pipeline Details (CircleCI API v2)

public struct PipelineDetails: Codable {
    public let id: String
    public let state: String?
    public let trigger: PipelineTrigger?
    public let vcs: PipelineVCS?

    public init(id: String, state: String?, trigger: PipelineTrigger?, vcs: PipelineVCS?) {
        self.id = id
        self.state = state
        self.trigger = trigger
        self.vcs = vcs
    }
}

public struct PipelineTrigger: Codable {
    public let type: String?
    public let actor: PipelineActor?
    public let receivedAt: String?

    public init(type: String?, actor: PipelineActor?, receivedAt: String?) {
        self.type = type
        self.actor = actor
        self.receivedAt = receivedAt
    }

    enum CodingKeys: String, CodingKey {
        case type
        case actor
        case receivedAt = "received_at"
    }
}

public struct PipelineActor: Codable {
    public let login: String?
    public let name: String?
    public let avatarUrl: String?

    public init(login: String?, name: String?, avatarUrl: String?) {
        self.login = login
        self.name = name
        self.avatarUrl = avatarUrl
    }

    enum CodingKeys: String, CodingKey {
        case login
        case name
        case avatarUrl = "avatar_url"
    }
}

public struct PipelineVCS: Codable {
    public let branch: String?

    public init(branch: String?) {
        self.branch = branch
    }
}
