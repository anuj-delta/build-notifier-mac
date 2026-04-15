import Foundation

public enum CircleCIMCPServiceError: Error, LocalizedError, Equatable {
    case authRequired
    case invalidProjectSlug(String)
    case buildNotFound(projectSlug: String, buildNumber: Int)

    public var errorDescription: String? {
        switch self {
        case .authRequired:
            return "No saved CircleCI login found. Open Build Notifier and sign in first."
        case .invalidProjectSlug(let projectSlug):
            return "Unknown project slug: \(projectSlug)"
        case .buildNotFound(let projectSlug, let buildNumber):
            return "Build #\(buildNumber) was not found for \(projectSlug)."
        }
    }
}

public struct ProjectActivitySummary: Codable, Equatable {
    public let projectSlug: String
    public let displayName: String
    public let vcsUrl: String?
    public let watched: Bool
    public let latestBuildNum: Int?
    public let latestBranch: String?
    public let latestStatus: String?
    public let latestActivityAt: String?
    public let latestSubject: String?
    public let buildUrl: String?
    public let workflowId: String?

    public init(
        projectSlug: String,
        displayName: String,
        vcsUrl: String?,
        watched: Bool,
        latestBuildNum: Int?,
        latestBranch: String?,
        latestStatus: String?,
        latestActivityAt: String?,
        latestSubject: String?,
        buildUrl: String?,
        workflowId: String?
    ) {
        self.projectSlug = projectSlug
        self.displayName = displayName
        self.vcsUrl = vcsUrl
        self.watched = watched
        self.latestBuildNum = latestBuildNum
        self.latestBranch = latestBranch
        self.latestStatus = latestStatus
        self.latestActivityAt = latestActivityAt
        self.latestSubject = latestSubject
        self.buildUrl = buildUrl
        self.workflowId = workflowId
    }
}

public struct BuildDetailsResponse: Codable, Equatable {
    public struct WorkflowSummary: Codable, Equatable {
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
    }

    public struct WorkflowJobSummary: Codable, Equatable {
        public let id: String
        public let name: String
        public let status: String
        public let type: String?
        public let approvedBy: String?
        public let projectSlug: String?
        public let startedAt: String?
        public let stoppedAt: String?
        public let jobNumber: Int?

        public init(
            id: String,
            name: String,
            status: String,
            type: String?,
            approvedBy: String?,
            projectSlug: String?,
            startedAt: String?,
            stoppedAt: String?,
            jobNumber: Int?
        ) {
            self.id = id
            self.name = name
            self.status = status
            self.type = type
            self.approvedBy = approvedBy
            self.projectSlug = projectSlug
            self.startedAt = startedAt
            self.stoppedAt = stoppedAt
            self.jobNumber = jobNumber
        }
    }

    public struct PipelineSummary: Codable, Equatable {
        public struct TriggerActorSummary: Codable, Equatable {
            public let login: String?
            public let name: String?
            public let avatarUrl: String?

            public init(login: String?, name: String?, avatarUrl: String?) {
                self.login = login
                self.name = name
                self.avatarUrl = avatarUrl
            }
        }

        public let id: String
        public let state: String?
        public let branch: String?
        public let triggerType: String?
        public let triggerReceivedAt: String?
        public let triggerActor: TriggerActorSummary?

        public init(
            id: String,
            state: String?,
            branch: String?,
            triggerType: String?,
            triggerReceivedAt: String?,
            triggerActor: TriggerActorSummary?
        ) {
            self.id = id
            self.state = state
            self.branch = branch
            self.triggerType = triggerType
            self.triggerReceivedAt = triggerReceivedAt
            self.triggerActor = triggerActor
        }
    }

    public let projectSlug: String
    public let vcsType: String
    public let buildNum: Int
    public let buildUrl: String?
    public let workflowUrl: String?
    public let branch: String?
    public let status: String?
    public let statusDisplayName: String
    public let outcome: String?
    public let lifecycle: String?
    public let vcsRevision: String?
    public let subject: String?
    public let body: String?
    public let why: String?
    public let queuedAt: String?
    public let startTime: String?
    public let stopTime: String?
    public let buildTimeMillis: Int?
    public let committerName: String?
    public let committerEmail: String?
    public let workflow: WorkflowSummary?
    public let workflowJobs: [WorkflowJobSummary]
    public let pipeline: PipelineSummary?

    public init(
        projectSlug: String,
        vcsType: String,
        buildNum: Int,
        buildUrl: String?,
        workflowUrl: String?,
        branch: String?,
        status: String?,
        statusDisplayName: String,
        outcome: String?,
        lifecycle: String?,
        vcsRevision: String?,
        subject: String?,
        body: String?,
        why: String?,
        queuedAt: String?,
        startTime: String?,
        stopTime: String?,
        buildTimeMillis: Int?,
        committerName: String?,
        committerEmail: String?,
        workflow: WorkflowSummary?,
        workflowJobs: [WorkflowJobSummary],
        pipeline: PipelineSummary?
    ) {
        self.projectSlug = projectSlug
        self.vcsType = vcsType
        self.buildNum = buildNum
        self.buildUrl = buildUrl
        self.workflowUrl = workflowUrl
        self.branch = branch
        self.status = status
        self.statusDisplayName = statusDisplayName
        self.outcome = outcome
        self.lifecycle = lifecycle
        self.vcsRevision = vcsRevision
        self.subject = subject
        self.body = body
        self.why = why
        self.queuedAt = queuedAt
        self.startTime = startTime
        self.stopTime = stopTime
        self.buildTimeMillis = buildTimeMillis
        self.committerName = committerName
        self.committerEmail = committerEmail
        self.workflow = workflow
        self.workflowJobs = workflowJobs
        self.pipeline = pipeline
    }
}

public struct CircleCIMCPService {
    public init() {}

    public func listProjectsByActivity(limit: Int = 25, watchedOnly: Bool = false) async throws -> [ProjectActivitySummary] {
        try await prepareAuthenticatedClient()

        let clampedLimit = Self.clamp(limit)
        let projects = try await CircleCIAPI.shared.getProjects()
        let recentBuilds = try await CircleCIAPI.shared.getRecentBuilds(limit: max(100, clampedLimit * 4))
        let watchedProjectSlugs = Set(Self.loadWatchedProjectSlugs())

        let latestBuildBySlug = recentBuilds.reduce(into: [String: Build]()) { latestBySlug, build in
            let current = latestBySlug[build.projectSlug]
            if current == nil || (build.activityDate ?? .distantPast) > (current?.activityDate ?? .distantPast) {
                latestBySlug[build.projectSlug] = build
            }
        }

        return projects
            .filter { project in
                guard watchedOnly else { return true }
                return watchedProjectSlugs.contains(project.slug)
            }
            .map { project in
                let latestBuild = latestBuildBySlug[project.slug]
                return ProjectActivitySummary(
                    projectSlug: project.slug,
                    displayName: project.displayName,
                    vcsUrl: project.vcsUrl,
                    watched: watchedProjectSlugs.contains(project.slug),
                    latestBuildNum: latestBuild?.buildNum,
                    latestBranch: latestBuild?.branch,
                    latestStatus: latestBuild?.buildStatus.rawValue,
                    latestActivityAt: latestBuild?.activityDate?.iso8601String,
                    latestSubject: latestBuild?.subject,
                    buildUrl: latestBuild?.workflowUrl ?? latestBuild?.buildUrl,
                    workflowId: latestBuild?.workflows?.workflowId
                )
            }
            .sorted(by: Self.compareProjectActivity)
            .prefix(clampedLimit)
            .map { $0 }
    }

    public func getBuildDetails(projectSlug: String, buildNumber: Int) async throws -> BuildDetailsResponse {
        try await prepareAuthenticatedClient()

        let project = try await resolveProject(from: projectSlug)

        do {
            let build = try await CircleCIAPI.shared.getBuild(
                vcsType: project.vcsTypePrefix,
                orgName: project.username,
                repoName: project.reponame,
                buildNum: buildNumber
            )

            let workflow = try await fetchWorkflowSummary(for: build)
            let workflowJobs = try await fetchWorkflowJobs(for: build)
            let pipeline = try await fetchPipelineSummary(for: workflow)

            return BuildDetailsResponse(
                projectSlug: project.slug,
                vcsType: project.vcsTypePrefix,
                buildNum: build.buildNum,
                buildUrl: build.buildUrl,
                workflowUrl: build.workflowUrl,
                branch: build.branch,
                status: build.status,
                statusDisplayName: build.buildStatus.displayName,
                outcome: build.outcome,
                lifecycle: build.lifecycle,
                vcsRevision: build.vcsRevision,
                subject: build.subject,
                body: build.body,
                why: build.why,
                queuedAt: build.queuedAt,
                startTime: build.startTime,
                stopTime: build.stopTime,
                buildTimeMillis: build.buildTimeMillis,
                committerName: build.committerName,
                committerEmail: build.committerEmail,
                workflow: workflow,
                workflowJobs: workflowJobs,
                pipeline: pipeline
            )
        } catch let error as CircleCIError {
            if case .httpError(404, _) = error {
                throw CircleCIMCPServiceError.buildNotFound(projectSlug: project.slug, buildNumber: buildNumber)
            }
            throw error
        }
    }

    private func prepareAuthenticatedClient() async throws {
        do {
            let token = try KeychainService.shared.getToken()
            await CircleCIAPI.shared.setToken(token)
        } catch {
            throw CircleCIMCPServiceError.authRequired
        }
    }

    private func resolveProject(from projectSlug: String) async throws -> Project {
        let normalized = Self.normalizeProjectSlug(projectSlug)
        let projects = try await CircleCIAPI.shared.getProjects()

        guard let project = projects.first(where: {
            $0.slug == normalized || "\($0.vcsTypePrefix)/\($0.slug)" == projectSlug
        }) else {
            throw CircleCIMCPServiceError.invalidProjectSlug(projectSlug)
        }

        return project
    }

    private func fetchWorkflowSummary(for build: Build) async throws -> BuildDetailsResponse.WorkflowSummary? {
        guard let workflowId = build.workflows?.workflowId else { return nil }
        let workflow = try await CircleCIAPI.shared.getWorkflow(workflowId: workflowId)
        return .init(
            id: workflow.id,
            name: workflow.name,
            status: workflow.status,
            pipelineId: workflow.pipelineId
        )
    }

    private func fetchWorkflowJobs(for build: Build) async throws -> [BuildDetailsResponse.WorkflowJobSummary] {
        guard let workflowId = build.workflows?.workflowId else { return [] }
        let jobs = try await CircleCIAPI.shared.getWorkflowJobs(workflowId: workflowId)
        return jobs.map {
            .init(
                id: $0.id,
                name: $0.name,
                status: $0.status,
                type: $0.type,
                approvedBy: $0.approvedBy,
                projectSlug: $0.projectSlug,
                startedAt: $0.startedAt,
                stoppedAt: $0.stoppedAt,
                jobNumber: $0.jobNumber
            )
        }
    }

    private func fetchPipelineSummary(
        for workflow: BuildDetailsResponse.WorkflowSummary?
    ) async throws -> BuildDetailsResponse.PipelineSummary? {
        guard let pipelineId = workflow?.pipelineId else { return nil }
        let pipeline = try await CircleCIAPI.shared.getPipeline(pipelineId: pipelineId)
        let actor = pipeline.trigger?.actor.map {
            BuildDetailsResponse.PipelineSummary.TriggerActorSummary(
                login: $0.login,
                name: $0.name,
                avatarUrl: $0.avatarUrl
            )
        }

        return .init(
            id: pipeline.id,
            state: pipeline.state,
            branch: pipeline.vcs?.branch,
            triggerType: pipeline.trigger?.type,
            triggerReceivedAt: pipeline.trigger?.receivedAt,
            triggerActor: actor
        )
    }

    public static func compareProjectActivity(_ lhs: ProjectActivitySummary, _ rhs: ProjectActivitySummary) -> Bool {
        switch (lhs.latestActivityAt, rhs.latestActivityAt) {
        case let (l?, r?) where l != r:
            return l > r
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.displayName.lowercased() < rhs.displayName.lowercased()
        }
    }

    private static func clamp(_ limit: Int) -> Int {
        min(max(limit, 1), 100)
    }

    private static func normalizeProjectSlug(_ projectSlug: String) -> String {
        let components = projectSlug.split(separator: "/").map(String.init)
        if components.count == 3 {
            return "\(components[1])/\(components[2])"
        }
        return projectSlug
    }

    public static func loadWatchedProjectSlugs(userDefaults: UserDefaults? = nil) -> [String] {
        let data: Data?
        if let userDefaults {
            data = userDefaults.data(forKey: BuildNotifierSharedDefaults.userPreferencesKey)
        } else {
            data = BuildNotifierSharedDefaults.loadData(forKey: BuildNotifierSharedDefaults.userPreferencesKey)
        }

        guard let data,
              let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let watchedProjects = jsonObject["watchedProjects"] as? [[String: Any]] else {
            return []
        }

        return watchedProjects.compactMap { watchedProject in
            if let orgName = watchedProject["orgName"] as? String,
               let repoName = watchedProject["repoName"] as? String {
                return "\(orgName)/\(repoName)"
            }

            if let id = watchedProject["id"] as? String {
                return normalizeProjectSlug(id)
            }

            return nil
        }
    }
}

private extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}
