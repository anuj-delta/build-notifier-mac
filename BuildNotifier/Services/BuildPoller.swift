import Foundation
import Combine
import BuildNotifierCore

// MARK: - Build Poller

private enum TriggerActorLookupResult {
    case matched
    case notMatched
    case unresolved
}

private enum PipelineActorCacheValue: Equatable {
    case known(String)
    case missing
}

private struct ProjectPollResult {
    let slug: String
    let builds: [Build]
    let approvals: [PendingApproval]
    let approvalSupport: [String: Bool]
    let workflowPipelineIds: [String: String]
    let pipelineActors: [String: PipelineActorCacheValue]
}

@MainActor
final class BuildPoller: ObservableObject {
    @Published private(set) var isPolling = false
    @Published private(set) var lastPollTime: Date?
    @Published private(set) var error: Error?
    
    private var scheduleTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var hasEstablishedBaseline = false
    private let fetchBuilds: (String, String, String, Int) async throws -> [Build]
    private let fetchWorkflowJobs: (String) async throws -> [WorkflowJob]
    private let fetchWorkflow: (String) async throws -> WorkflowDetails
    private let fetchPipeline: (String) async throws -> PipelineDetails
    private let sendBuildStartedNotification: (Build, Bool) -> Void
    private let sendBuildFailureNotification: (Build, Bool) -> Void
    private let sendBuildSuccessNotification: (Build, Bool) -> Void
    private let sendPendingApprovalNotification: (PendingApproval, Bool) -> Void
    private var cachedPipelineIdByWorkflowId: [String: String] = [:]
    private var cachedActorByPipelineId: [String: PipelineActorCacheValue] = [:]
    
    weak var appState: AppState?
    
    init(
        fetchBuilds: ((String, String, String, Int) async throws -> [Build])? = nil,
        fetchWorkflowJobs: ((String) async throws -> [WorkflowJob])? = nil,
        fetchWorkflow: ((String) async throws -> WorkflowDetails)? = nil,
        fetchPipeline: ((String) async throws -> PipelineDetails)? = nil,
        sendBuildStartedNotification: ((Build, Bool) -> Void)? = nil,
        sendBuildFailureNotification: ((Build, Bool) -> Void)? = nil,
        sendBuildSuccessNotification: ((Build, Bool) -> Void)? = nil,
        sendPendingApprovalNotification: ((PendingApproval, Bool) -> Void)? = nil
    ) {
        self.fetchBuilds = fetchBuilds ?? { vcsType, orgName, repoName, limit in
            try await CircleCIAPI.shared.getBuilds(
                vcsType: vcsType,
                orgName: orgName,
                repoName: repoName,
                limit: limit
            )
        }
        self.fetchWorkflowJobs = fetchWorkflowJobs ?? { workflowId in
            try await CircleCIAPI.shared.getWorkflowJobs(workflowId: workflowId)
        }
        self.fetchWorkflow = fetchWorkflow ?? { workflowId in
            try await CircleCIAPI.shared.getWorkflow(workflowId: workflowId)
        }
        self.fetchPipeline = fetchPipeline ?? { pipelineId in
            try await CircleCIAPI.shared.getPipeline(pipelineId: pipelineId)
        }
        self.sendBuildStartedNotification = sendBuildStartedNotification ?? { build, soundEnabled in
            NotificationManager.shared.sendBuildStartedNotification(build: build, soundEnabled: soundEnabled)
        }
        self.sendBuildFailureNotification = sendBuildFailureNotification ?? { build, soundEnabled in
            NotificationManager.shared.sendBuildFailureNotification(build: build, soundEnabled: soundEnabled)
        }
        self.sendBuildSuccessNotification = sendBuildSuccessNotification ?? { build, soundEnabled in
            NotificationManager.shared.sendBuildSuccessNotification(build: build, soundEnabled: soundEnabled)
        }
        self.sendPendingApprovalNotification = sendPendingApprovalNotification ?? { approval, soundEnabled in
            NotificationManager.shared.sendPendingApprovalNotification(approval: approval, soundEnabled: soundEnabled)
        }
    }
    
    // MARK: - Start/Stop Polling
    
    func startPolling(interval: TimeInterval = 60) {
        stopPolling()

        isPolling = true
        hasEstablishedBaseline = false
        
        // Poll immediately
        poll()
        
        // Then poll on interval
        scheduleTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                self.poll()
            }
        }
    }
    
    func stopPolling() {
        scheduleTask?.cancel()
        scheduleTask = nil
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
        hasEstablishedBaseline = false
    }
    
    func poll() {
        pollTask?.cancel()
        pollTask = Task {
            await performPoll()
        }
    }

    func checkNow() async {
        await performPoll()
    }
    
    // MARK: - Poll Implementation
    
    private func performPoll() async {
        guard let appState = appState else { return }
        
        let watchedProjects = appState.preferences.watchedProjects.filter { $0.isEnabled }
        guard !watchedProjects.isEmpty else {
            lastPollTime = Date()
            return
        }
        
        error = nil
        
        // Store previous builds for comparison
        let previousBuilds = appState.buildsByProject
        
        // Capture current user info for filtering (main actor isolated)
        let currentUserLogin = appState.currentUser?.login
        let currentUserEmail = appState.currentUser?.selectedEmail
        let currentUserName = appState.currentUser?.name
        let fetchBuilds = self.fetchBuilds
        let fetchWorkflowJobs = self.fetchWorkflowJobs
        let fetchWorkflow = self.fetchWorkflow
        let fetchPipeline = self.fetchPipeline
        let cachedPipelineIdByWorkflowId = self.cachedPipelineIdByWorkflowId
        let cachedActorByPipelineId = self.cachedActorByPipelineId
        
        // Fetch builds for each watched project
        var newBuildsByProject: [String: [Build]] = [:]
        var newPendingApprovals: [PendingApproval] = []
        var workflowApprovalSupport: [String: Bool] = [:]
        var mergedWorkflowPipelineIds = cachedPipelineIdByWorkflowId
        var mergedPipelineActors = cachedActorByPipelineId

        await withTaskGroup(of: ProjectPollResult?.self) { group in
            for project in watchedProjects {
                let previousProjectBuilds = previousBuilds[project.slug] ?? []
                group.addTask {
                    do {
                        var builds = try await fetchBuilds(
                            project.vcsType,
                            project.orgName,
                            project.repoName,
                            30
                        )
                        
                        // Filter to user's builds if needed
                        if project.followMode == .mine {
                            var workflowMatchesCurrentUser: [String: TriggerActorLookupResult] = [:]
                            var workflowPipelineIds = cachedPipelineIdByWorkflowId
                            var pipelineActors = cachedActorByPipelineId
                            var filteredBuilds: [Build] = []

                            for build in builds {
                                if Self.matchesCurrentUserFromCommit(
                                    build: build,
                                    currentUserLogin: currentUserLogin,
                                    currentUserEmail: currentUserEmail,
                                    currentUserName: currentUserName
                                ) {
                                    filteredBuilds.append(build)
                                    continue
                                }

                                guard let workflowId = build.workflows?.workflowId else {
                                    continue
                                }

                                let matchesCurrentUser: Bool
                                if let cached = workflowMatchesCurrentUser[workflowId] {
                                    matchesCurrentUser = cached == .matched || (
                                        cached == .unresolved &&
                                        Self.wasPreviouslyVisible(build, in: previousProjectBuilds)
                                    )
                                } else {
                                    let resolved = await Self.matchesCurrentUserFromTriggerActor(
                                        workflowId: workflowId,
                                        currentUserLogin: currentUserLogin,
                                        fetchWorkflow: fetchWorkflow,
                                        fetchPipeline: fetchPipeline,
                                        cachedPipelineIdByWorkflowId: &workflowPipelineIds,
                                        cachedActorByPipelineId: &pipelineActors
                                    )
                                    workflowMatchesCurrentUser[workflowId] = resolved
                                    matchesCurrentUser = resolved == .matched || (
                                        resolved == .unresolved &&
                                        Self.wasPreviouslyVisible(build, in: previousProjectBuilds)
                                    )
                                }

                                if matchesCurrentUser {
                                    filteredBuilds.append(build)
                                }
                            }

                            builds = filteredBuilds

                            // Carry cache updates back to the main actor after the task completes.
                            let approvalsResult = try await Self.fetchApprovals(
                                for: builds,
                                fetchWorkflowJobs: fetchWorkflowJobs
                            )
                            return ProjectPollResult(
                                slug: project.slug,
                                builds: builds,
                                approvals: approvalsResult.approvals,
                                approvalSupport: approvalsResult.approvalSupport,
                                workflowPipelineIds: workflowPipelineIds,
                                pipelineActors: pipelineActors
                            )
                        }

                        let approvalsResult = try await Self.fetchApprovals(
                            for: builds,
                            fetchWorkflowJobs: fetchWorkflowJobs
                        )
                        return ProjectPollResult(
                            slug: project.slug,
                            builds: builds,
                            approvals: approvalsResult.approvals,
                            approvalSupport: approvalsResult.approvalSupport,
                            workflowPipelineIds: [:],
                            pipelineActors: [:]
                        )
                    } catch {
                        return nil
                    }
                }
            }
            
            for await result in group {
                if let result {
                    newBuildsByProject[result.slug] = result.builds
                    newPendingApprovals.append(contentsOf: result.approvals)
                    workflowApprovalSupport.merge(result.approvalSupport) { _, new in new }
                    mergedWorkflowPipelineIds.merge(result.workflowPipelineIds) { _, new in new }
                    mergedPipelineActors.merge(result.pipelineActors) { _, new in new }
                }
            }
        }
        
        // Update state
        appState.buildsByProject = newBuildsByProject
        appState.pendingApprovals = newPendingApprovals
        appState.mergeWorkflowApprovalSupport(workflowApprovalSupport)
        self.cachedPipelineIdByWorkflowId = mergedWorkflowPipelineIds
        self.cachedActorByPipelineId = mergedPipelineActors
        lastPollTime = Date()

        if !hasEstablishedBaseline {
            await establishNotificationBaseline(
                current: newBuildsByProject,
                currentApprovals: newPendingApprovals
            )
            hasEstablishedBaseline = true
            return
        }

        // Check for status changes and send notifications
        await checkForStatusChanges(
            previous: previousBuilds,
            current: newBuildsByProject,
            previousApprovals: appState.notifiedApprovals,
            currentApprovals: newPendingApprovals,
            preferences: appState.preferences
        )
        
        // Update notified approvals
        appState.notifiedApprovals = Set(newPendingApprovals.map { $0.id })
    }

    private func establishNotificationBaseline(
        current: [String: [Build]],
        currentApprovals: [PendingApproval]
    ) async {
        guard let appState = appState else { return }
        let fetchWorkflowJobs = self.fetchWorkflowJobs

        var startedWorkflows = Set<String>()
        var failedWorkflows = Set<String>()
        var successWorkflows = Set<String>()
        var buildsByWorkflow: [String: [Build]] = [:]

        for (_, currentBuilds) in current {
            for build in currentBuilds {
                guard let workflowId = build.workflows?.workflowId else { continue }
                buildsByWorkflow[workflowId, default: []].append(build)
            }
        }

        for (workflowId, builds) in buildsByWorkflow {
            if builds.contains(where: { $0.buildStatus.isRunning }) {
                startedWorkflows.insert(workflowId)
            }

            if builds.contains(where: { $0.buildStatus.isFailure }) {
                failedWorkflows.insert(workflowId)
                continue
            }

            do {
                let allJobs = try await fetchWorkflowJobs(workflowId)
                let hasIncompleteJobs = allJobs.contains { job in
                    let status = job.status
                    return status == "running" || status == "queued" ||
                           status == "blocked" || status == "not_run" ||
                           status == "on_hold"
                }

                if !hasIncompleteJobs && allJobs.allSatisfy({ $0.status == "success" }) {
                    successWorkflows.insert(workflowId)
                }
            } catch {
                // Ignore transient baseline fetch errors; future polls can recover.
            }
        }

        appState.notifiedApprovals = Set(currentApprovals.map(\.id))
        appState.notifiedStartedWorkflows = startedWorkflows
        appState.notifiedFailedWorkflows = failedWorkflows
        appState.notifiedSuccessWorkflows = successWorkflows
    }
    
    // MARK: - Status Change Detection
    
    private func checkForStatusChanges(
        previous: [String: [Build]],
        current: [String: [Build]],
        previousApprovals: Set<String>,
        currentApprovals: [PendingApproval],
        preferences: UserPreferences
    ) async {
        guard let appState = appState else { return }

        // Check global notifications toggle first
        guard preferences.notificationsEnabled else { return }

        let soundEnabled = preferences.notificationSoundEnabled
        let fetchWorkflowJobs = self.fetchWorkflowJobs

        // Group all builds by workflow for workflow-level notifications
        var buildsByWorkflow: [String: [Build]] = [:]
        for (_, currentBuilds) in current {
            for build in currentBuilds {
                if let workflowId = build.workflows?.workflowId {
                    buildsByWorkflow[workflowId, default: []].append(build)
                }
            }
        }

        // Track notified workflows
        var newSuccessWorkflows = appState.notifiedSuccessWorkflows
        var newFailedWorkflows = appState.notifiedFailedWorkflows
        var newStartedWorkflows = appState.notifiedStartedWorkflows

        for (workflowId, builds) in buildsByWorkflow {
            // STARTED: Notify once when workflow has any running job
            if preferences.notifyOnBuildStarted {
                if !appState.notifiedStartedWorkflows.contains(workflowId) {
                    if builds.contains(where: { $0.buildStatus.isRunning }) {
                        if let representativeBuild = builds.first {
                            sendBuildStartedNotification(representativeBuild, soundEnabled)
                            newStartedWorkflows.insert(workflowId)
                        }
                    }
                }
            }

            // FAILURE: Notify once when ANY job in workflow fails
            if preferences.notifyOnFailure {
                if !appState.notifiedFailedWorkflows.contains(workflowId) {
                    if let failedBuild = builds.first(where: { $0.buildStatus.isFailure }) {
                        sendBuildFailureNotification(failedBuild, soundEnabled)
                        newFailedWorkflows.insert(workflowId)
                    }
                }
            }

            // SUCCESS: Notify once when ALL jobs in workflow succeed
            // Use v2 API to check ALL jobs (v1.1 may not include not-yet-started jobs)
            if preferences.notifyOnSuccess {
                if !appState.notifiedSuccessWorkflows.contains(workflowId) {
                    do {
                        let allJobs = try await fetchWorkflowJobs(workflowId)

                        // Check if any jobs are still incomplete
                        let hasIncompleteJobs = allJobs.contains { job in
                            let status = job.status
                            return status == "running" || status == "queued" ||
                                   status == "blocked" || status == "not_run" ||
                                   status == "on_hold"
                        }

                        // Only succeed if no incomplete jobs AND all jobs succeeded
                        if !hasIncompleteJobs {
                            let allSucceeded = allJobs.allSatisfy { $0.status == "success" }
                            if allSucceeded, let representativeBuild = builds.first {
                                sendBuildSuccessNotification(representativeBuild, soundEnabled)
                                newSuccessWorkflows.insert(workflowId)
                            }
                        }
                    } catch {
                        // Ignore API errors, will retry on next poll
                    }
                }
            }
        }

        // Update notified workflows
        appState.notifiedSuccessWorkflows = newSuccessWorkflows
        appState.notifiedFailedWorkflows = newFailedWorkflows
        appState.notifiedStartedWorkflows = newStartedWorkflows

        // Check for new pending approvals
        if preferences.notifyOnPendingApproval {
            for approval in currentApprovals {
                if !previousApprovals.contains(approval.id) {
                    sendPendingApprovalNotification(approval, soundEnabled)
                }
            }
        }
    }

    private nonisolated static func matchesCurrentUserFromCommit(
        build: Build,
        currentUserLogin: String?,
        currentUserEmail: String?,
        currentUserName: String?
    ) -> Bool {
        if let email = currentUserEmail, let committerEmail = build.committerEmail,
           committerEmail.lowercased() == email.lowercased() {
            return true
        }
        if let name = currentUserName, let committerName = build.committerName,
           committerName.lowercased() == name.lowercased() {
            return true
        }
        if let login = currentUserLogin, let committerName = build.committerName,
           committerName.lowercased() == login.lowercased() {
            return true
        }
        return false
    }

    private nonisolated static func fetchApprovals(
        for builds: [Build],
        fetchWorkflowJobs: (String) async throws -> [WorkflowJob]
    ) async throws -> (approvals: [PendingApproval], approvalSupport: [String: Bool]) {
        var approvals: [PendingApproval] = []
        var approvalSupport: [String: Bool] = [:]
        var checkedWorkflowIds = Set<String>()
        let recentBuilds = builds.prefix(20)

        for build in recentBuilds {
            guard let workflowId = build.workflows?.workflowId,
                  !checkedWorkflowIds.contains(workflowId) else {
                continue
            }
            checkedWorkflowIds.insert(workflowId)

            do {
                let jobs = try await fetchWorkflowJobs(workflowId)
                approvalSupport[workflowId] = jobs.contains(where: \.canStillRequireApproval)

                let hasInProgressJobs = jobs.contains { job in
                    !job.isApprovalJob && (job.status == "running" || job.status == "queued")
                }

                if !hasInProgressJobs {
                    let pendingJobs = jobs.filter { $0.isPendingApproval }
                    for job in pendingJobs {
                        approvals.append(PendingApproval(workflowId: workflowId, job: job, build: build))
                    }
                }
            } catch {
                continue
            }
        }

        return (approvals, approvalSupport)
    }

    private nonisolated static func wasPreviouslyVisible(_ build: Build, in previousBuilds: [Build]) -> Bool {
        if let workflowId = build.workflows?.workflowId {
            return previousBuilds.contains { $0.workflows?.workflowId == workflowId }
        }
        return previousBuilds.contains { $0.id == build.id }
    }

    private nonisolated static func matchesCurrentUserFromTriggerActor(
        workflowId: String,
        currentUserLogin: String?,
        fetchWorkflow: (String) async throws -> WorkflowDetails,
        fetchPipeline: (String) async throws -> PipelineDetails,
        cachedPipelineIdByWorkflowId: inout [String: String],
        cachedActorByPipelineId: inout [String: PipelineActorCacheValue]
    ) async -> TriggerActorLookupResult {
        guard let currentUserLogin = currentUserLogin?.lowercased() else { return .notMatched }

        do {
            let pipelineId: String
            if let cached = cachedPipelineIdByWorkflowId[workflowId] {
                pipelineId = cached
            } else {
                let workflow = try await fetchWorkflow(workflowId)
                guard let resolvedPipelineId = workflow.pipelineId else { return .unresolved }
                cachedPipelineIdByWorkflowId[workflowId] = resolvedPipelineId
                pipelineId = resolvedPipelineId
            }

            let actorLogin: String?
            if let cached = cachedActorByPipelineId[pipelineId] {
                switch cached {
                case .known(let login):
                    actorLogin = login
                case .missing:
                    actorLogin = nil
                }
            } else {
                let pipeline = try await fetchPipeline(pipelineId)
                if let resolvedLogin = pipeline.trigger?.actor?.login?.lowercased() {
                    cachedActorByPipelineId[pipelineId] = .known(resolvedLogin)
                    actorLogin = resolvedLogin
                } else {
                    cachedActorByPipelineId[pipelineId] = .missing
                    actorLogin = nil
                }
            }

            guard let actorLogin else { return .unresolved }
            return actorLogin == currentUserLogin ? .matched : .notMatched
        } catch {
            return .unresolved
        }
    }
}
