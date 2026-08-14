import Foundation
import Combine

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
    private var baselinedProjectSlugs: Set<String> = []
    private var unresolvedBaselineWorkflowIds: Set<String> = []
    private let fetchBuilds: (String, String, String, Int) async throws -> [Build]
    private let fetchWorkflowJobs: (String) async throws -> [WorkflowJob]
    private let fetchWorkflow: (String) async throws -> WorkflowDetails
    private let fetchPipeline: (String) async throws -> PipelineDetails
    private let sendBuildStartedNotification: (Build, Bool) -> Void
    private let sendBuildFailureNotification: (Build, Bool) -> Void
    private let sendBuildSuccessNotification: (Build, Bool) -> Void
    private let sendPendingApprovalNotification: (PendingApproval, Bool) -> Void
    private let now: () -> Date
    private var cachedPipelineIdByWorkflowId: [String: String] = [:]
    private var cachedActorByPipelineId: [String: PipelineActorCacheValue] = [:]
    private var cachedTerminalWorkflowStatusById: [String: String] = [:]

    /// Per-poll cache of every v2 status fetched this cycle, including non-terminal ones.
    /// A workflow can be both a devnet-deploy candidate and an on-screen row; the two
    /// resolvers run sequentially, so the first warms this and the second reuses it instead
    /// of making a second round-trip for a still-running workflow. Reset at each poll start.
    private var workflowStatusThisPoll: [String: String] = [:]

    /// v2 workflow statuses that never change again, so they can be cached across polls.
    /// `running`, `on_hold`, `not_run`, and `failing` are transient and always refetched.
    private static let terminalWorkflowStatuses: Set<String> = ["success", "failed", "error", "canceled", "unauthorized"]

    /// Cap on how many recent deploy workflows to probe per project and environment when
    /// resolving the live branch. The live deploy is effectively always among the newest few.
    private static let maxDeployWorkflowChecks = 8

    /// Upper bound on the terminal-status cache so memory stays flat across a long session.
    private static let maxCachedWorkflowStatuses = 500
    
    weak var appState: AppState?
    
    init(
        fetchBuilds: ((String, String, String, Int) async throws -> [Build])? = nil,
        fetchWorkflowJobs: ((String) async throws -> [WorkflowJob])? = nil,
        fetchWorkflow: ((String) async throws -> WorkflowDetails)? = nil,
        fetchPipeline: ((String) async throws -> PipelineDetails)? = nil,
        sendBuildStartedNotification: ((Build, Bool) -> Void)? = nil,
        sendBuildFailureNotification: ((Build, Bool) -> Void)? = nil,
        sendBuildSuccessNotification: ((Build, Bool) -> Void)? = nil,
        sendPendingApprovalNotification: ((PendingApproval, Bool) -> Void)? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.now = now
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
        baselinedProjectSlugs.removeAll()
        unresolvedBaselineWorkflowIds.removeAll()
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

        workflowStatusThisPoll.removeAll(keepingCapacity: true)

        // Store previous builds for comparison
        let previousBuilds = appState.buildsByProject
        
        // Capture current user info for filtering (main actor isolated)
        let currentUserLogin = appState.currentUser?.login
        let identities = appState.currentUser?.identities ?? []
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
        var successfulResults: [ProjectPollResult] = []

        await withTaskGroup(of: ProjectPollResult?.self) { group in
            for project in watchedProjects {
                let previousProjectBuilds = previousBuilds[project.slug] ?? []
                group.addTask {
                    do {
                        var builds = try await fetchBuilds(
                            project.vcsType,
                            project.orgName,
                            project.repoName,
                            100
                        )
                        
                        // Filter to user's builds if needed
                        if project.followMode == .mine {
                            var workflowMatchesCurrentUser: [String: TriggerActorLookupResult] = [:]
                            var workflowPipelineIds = cachedPipelineIdByWorkflowId
                            var pipelineActors = cachedActorByPipelineId
                            var filteredBuilds: [Build] = []

                            for build in builds {
                                if Self.matchesCurrentUserFromCommit(build: build, identities: identities) {
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
                    successfulResults.append(result)
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

        // Merge the live branch rather than replace: a deploy stays live until a newer one
        // succeeds, so a project that yields no fresh success this poll (or whose v2 status
        // fetch transiently failed) keeps its last known branch instead of the badge
        // flickering off. The in-flight branch is replaced wholesale so a finished or failed
        // deploy clears at once - on failure the row falls back to the retained live branch.
        let resolvedDeploys = await resolveDeployedBranches(
            buildsByProject: newBuildsByProject,
            productionBranches: appState.preferences.productionBranches
        )
        for (env, bySlug) in resolvedDeploys.deployed {
            appState.deployedBranchBySlugByEnv[env, default: [:]].merge(bySlug) { _, new in new }
        }
        // Replace in-flight state only for projects actually polled this cycle: a project whose
        // build fetch failed keeps its prior deploying badge instead of flickering off, while a
        // finished or failed deploy on a polled project clears at once.
        let polledSlugs = Set(newBuildsByProject.keys)
        for env in DeployEnvironment.allCases {
            var bySlug = (appState.deployingBranchBySlugByEnv[env] ?? [:]).filter { !polledSlugs.contains($0.key) }
            for (slug, branch) in resolvedDeploys.deploying[env] ?? [:] {
                bySlug[slug] = branch
            }
            appState.deployingBranchBySlugByEnv[env] = bySlug.isEmpty ? nil : bySlug
        }
        appState.refreshDeploySpinner()
        appState.regroupCards()

        // Resolve the authoritative v2 status for each on-screen row's workflow. v1.1 build
        // status lags v2, so a finished workflow can still report a running job for a short
        // window; the row trusts v2 when available and falls back to v1.1 otherwise.
        let representativeWorkflowIds = Set(
            appState.repoCards
                .flatMap(\.branches)
                .compactMap { $0.build?.workflows?.workflowId }
        )
        let resolvedStatuses = await resolveWorkflowStatuses(workflowIds: representativeWorkflowIds)
        // Keep the last-known status for an on-screen workflow whose v2 fetch failed this
        // poll (so the row doesn't flicker back to v1.1), but drop workflows that scrolled
        // off screen so the map stays bounded to what's displayed.
        var mergedStatuses = appState.workflowStatusByWorkflowId.filter { representativeWorkflowIds.contains($0.key) }
        mergedStatuses.merge(resolvedStatuses) { _, new in new }
        appState.workflowStatusByWorkflowId = mergedStatuses

        let watchedProjectSlugs = Set(watchedProjects.map(\.slug))
        baselinedProjectSlugs.formIntersection(watchedProjectSlugs)

        var liveBuildsByProject: [String: [Build]] = [:]
        var livePendingApprovals: [PendingApproval] = []
        for result in successfulResults {
            if baselinedProjectSlugs.contains(result.slug) {
                liveBuildsByProject[result.slug] = result.builds
                livePendingApprovals.append(contentsOf: result.approvals)
                continue
            }

            await establishNotificationBaseline(
                currentBuilds: result.builds,
                currentApprovals: result.approvals
            )
            baselinedProjectSlugs.insert(result.slug)
        }

        if !liveBuildsByProject.isEmpty || !livePendingApprovals.isEmpty {
            await checkForStatusChanges(
                previous: previousBuilds,
                current: liveBuildsByProject,
                previousApprovals: appState.notifiedApprovals,
                currentApprovals: livePendingApprovals,
                preferences: appState.preferences
            )
        }
        
        // Approval request IDs are immutable, so retain them for the session.
        // A transient project fetch must not make an old approval notify again.
        appState.notifiedApprovals.formUnion(newPendingApprovals.map(\.id))
    }

    /// v2 rollup statuses that mean a deploy is still in flight (not yet terminal).
    private static let inProgressWorkflowStatuses: Set<String> = ["running", "on_hold", "failing"]

    /// For each environment and project, the branch live there (newest deploy workflow whose
    /// v2 rollup status is `success`) and the branch mid-deploy (newest deploy workflow that
    /// is still in flight). v1.1 can't distinguish a pending deploy from a finished one, so the
    /// checks run against the workflow status CircleCI itself reports.
    private func resolveDeployedBranches(
        buildsByProject: [String: [Build]],
        productionBranches: [String]
    ) async -> (deployed: [DeployEnvironment: [String: String]], deploying: [DeployEnvironment: [String: String]]) {
        typealias Resolved = (env: DeployEnvironment, slug: String, deployed: String?, deploying: String?)
        return await withTaskGroup(of: Resolved?.self) { group in
            for env in DeployEnvironment.allCases {
                for (slug, builds) in buildsByProject {
                    let candidates = env.deployWorkflowsNewestFirst(
                        builds: builds,
                        productionBranches: productionBranches
                    )
                    group.addTask { @MainActor in
                        var deployed: String?
                        var deploying: String?
                        for candidate in candidates.prefix(Self.maxDeployWorkflowChecks) {
                            let status = await self.workflowStatus(candidate.workflowId)
                            if deploying == nil, let status, Self.inProgressWorkflowStatuses.contains(status) {
                                deploying = candidate.branch
                            }
                            if deployed == nil, status == "success" {
                                deployed = candidate.branch
                            }
                            if deployed != nil, deploying != nil { break }
                        }
                        if deployed == nil, candidates.count > Self.maxDeployWorkflowChecks {
                            print("[BuildPoller] \(slug): no successful \(env.label) deploy in newest \(Self.maxDeployWorkflowChecks) workflows; older ones not probed")
                        }
                        if deployed == nil, deploying == nil { return nil }
                        return (env, slug, deployed, deploying)
                    }
                }
            }
            var deployed: [DeployEnvironment: [String: String]] = [:]
            var deploying: [DeployEnvironment: [String: String]] = [:]
            for await found in group {
                guard let found else { continue }
                if let branch = found.deployed { deployed[found.env, default: [:]][found.slug] = branch }
                if let branch = found.deploying { deploying[found.env, default: [:]][found.slug] = branch }
            }
            return (deployed, deploying)
        }
    }

    /// v2 rollup status per workflow id, resolved in parallel and reusing the terminal-status
    /// cache. Workflows whose status can't be fetched this poll are omitted, so the row falls
    /// back to its v1.1 build status rather than flickering.
    private func resolveWorkflowStatuses(workflowIds: Set<String>) async -> [String: String] {
        await withTaskGroup(of: (id: String, status: String)?.self) { group in
            for workflowId in workflowIds {
                group.addTask { @MainActor in
                    guard let status = await self.workflowStatus(workflowId) else { return nil }
                    return (workflowId, status)
                }
            }
            var result: [String: String] = [:]
            for await entry in group {
                if let entry { result[entry.id] = entry.status }
            }
            return result
        }
    }

    /// Job statuses that mark a workflow as failed when its rollup is unreliable.
    private static let failureJobStatuses: Set<String> = ["failed", "error", "timedout", "infrastructure_fail"]

    /// Job statuses that mean a job is still in flight, so the workflow isn't actually done.
    private static let inProgressJobStatuses: Set<String> = ["running", "queued", "blocked", "on_hold"]

    /// v2 workflow rollup status, caching terminal results so finished workflows aren't
    /// refetched on later polls. Returns nil on fetch error (caller treats as not-deployed).
    private func workflowStatus(_ workflowId: String) async -> String? {
        if let thisPoll = workflowStatusThisPoll[workflowId] { return thisPoll }
        if let cached = cachedTerminalWorkflowStatusById[workflowId] { return cached }
        do {
            let workflow = try await fetchWorkflow(workflowId)
            guard var status = workflow.status else { return nil }

            // A rerun-from-failed can leave the rollup stuck at a non-terminal value
            // (`running`/`failing`) even though every job has finished, which would spin the
            // row forever. CircleCI sometimes never sets `stopped_at` on these reruns either,
            // so trust the jobs over the stuck rollup once the workflow has either stopped or
            // is a rerun. `deriveTerminalStatusFromJobs` still returns nil while any job is in
            // flight, so a genuinely running rerun won't resolve early.
            if !Self.terminalWorkflowStatuses.contains(status),
               workflow.stoppedAt != nil || workflow.isRerun,
               let derived = await deriveTerminalStatusFromJobs(workflowId) {
                status = derived
            }

            workflowStatusThisPoll[workflowId] = status
            if Self.terminalWorkflowStatuses.contains(status) {
                // Bounded so a long-running session can't accumulate an entry per
                // workflow ever seen; on overflow we drop the cache and refetch lazily.
                if cachedTerminalWorkflowStatusById.count >= Self.maxCachedWorkflowStatuses {
                    cachedTerminalWorkflowStatusById.removeAll(keepingCapacity: true)
                }
                cachedTerminalWorkflowStatusById[workflowId] = status
            }
            return status
        } catch {
            return nil
        }
    }

    /// Terminal status of a stopped workflow whose rollup is unreliable, read off its jobs:
    /// any failed job -> `failed`, else any canceled job -> `canceled`, else `success`.
    /// Returns nil if the jobs can't be fetched or the workflow has none, so the caller keeps
    /// the original rollup status rather than guessing.
    private func deriveTerminalStatusFromJobs(_ workflowId: String) async -> String? {
        guard let jobs = try? await fetchWorkflowJobs(workflowId), !jobs.isEmpty else { return nil }
        if jobs.contains(where: { Self.failureJobStatuses.contains($0.status) }) { return "failed" }
        if jobs.contains(where: { $0.status == "canceled" }) { return "canceled" }
        // Only claim success if nothing is still in flight. If `stopped_at` is set yet a job
        // still reads running/queued (an API divergence beyond the rerun-from-failed bug this
        // handles), keep the original rollup status rather than silently reporting success.
        if jobs.contains(where: { Self.inProgressJobStatuses.contains($0.status) }) { return nil }
        return "success"
    }

    private func establishNotificationBaseline(
        currentBuilds: [Build],
        currentApprovals: [PendingApproval]
    ) async {
        guard let appState = appState else { return }
        let fetchWorkflowJobs = self.fetchWorkflowJobs

        var startedWorkflows = Set<String>()
        var failedWorkflows = Set<String>()
        var successWorkflows = Set<String>()
        var buildsByWorkflow: [String: [Build]] = [:]

        for build in currentBuilds {
            guard let workflowId = build.workflows?.workflowId else { continue }
            buildsByWorkflow[workflowId, default: []].append(build)
        }

        for (workflowId, builds) in buildsByWorkflow {
            if builds.contains(where: { $0.buildStatus.isRunning }) {
                startedWorkflows.insert(workflowId)
            }

            if builds.contains(where: { $0.buildStatus.isFailure }) {
                failedWorkflows.insert(workflowId)
                unresolvedBaselineWorkflowIds.remove(workflowId)
                continue
            }

            do {
                let allJobs = try await fetchWorkflowJobs(workflowId)
                guard !allJobs.isEmpty else {
                    unresolvedBaselineWorkflowIds.insert(workflowId)
                    continue
                }
                let hasIncompleteJobs = allJobs.contains { job in
                    let status = job.status
                    return status == "running" || status == "queued" ||
                           status == "blocked" || status == "not_run" ||
                           status == "on_hold"
                }

                if !hasIncompleteJobs && allJobs.allSatisfy({ $0.status == "success" }) {
                    successWorkflows.insert(workflowId)
                }
                unresolvedBaselineWorkflowIds.remove(workflowId)
            } catch {
                // The first successfully resolved state is still part of the
                // startup snapshot and must be absorbed without notifying.
                unresolvedBaselineWorkflowIds.insert(workflowId)
            }
        }

        appState.notifiedApprovals.formUnion(currentApprovals.map(\.id))
        appState.notifiedStartedWorkflows.formUnion(startedWorkflows)
        appState.notifiedFailedWorkflows.formUnion(failedWorkflows)
        appState.notifiedSuccessWorkflows.formUnion(successWorkflows)
        appState.celebratedSuccessWorkflows.formUnion(successWorkflows)
        appState.playedFailureSoundWorkflows.formUnion(failedWorkflows)
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

        // Celebrations gate only on their own prefs, so they must be able to run
        // even when notifications are globally disabled.
        let notificationsEnabled = preferences.notificationsEnabled
        let celebrationsWanted = preferences.celebrateProdSuccess
            || preferences.celebrateDeployedBranches
            || preferences.playFailureSound
        guard notificationsEnabled || celebrationsWanted else { return }

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

        // Track notified / celebrated workflows
        var newSuccessWorkflows = appState.notifiedSuccessWorkflows
        var newFailedWorkflows = appState.notifiedFailedWorkflows
        var newStartedWorkflows = appState.notifiedStartedWorkflows
        var newCelebratedSuccess = appState.celebratedSuccessWorkflows
        var newPlayedFailureSound = appState.playedFailureSoundWorkflows
        var newUnresolvedBaselineWorkflows = unresolvedBaselineWorkflowIds

        for (workflowId, builds) in buildsByWorkflow {
            // Confetti and failure sound only fire for branches the user cares
            // about: production-branch patterns plus branches deployed via the
            // Deploy-a-Branch modal this session.
            let branch = builds.first?.branch
            let isProdBranch = ProductionBranchMatcher.isProduction(
                branch: branch,
                patterns: preferences.productionBranches
            )
            let isDeployedBranch = branch.map {
                appState.deployedBranchKeys.contains(
                    AppState.deployKey(projectSlug: builds.first?.projectSlug ?? "", branch: $0)
                )
            } ?? false

            // STARTED: Notify once when workflow has any running job
            if notificationsEnabled && preferences.notifyOnBuildStarted {
                if !appState.notifiedStartedWorkflows.contains(workflowId) {
                    if builds.contains(where: { $0.buildStatus.isRunning }) {
                        if let representativeBuild = builds.first {
                            if NotificationManager.isFresh(representativeBuild.stateChangeDate, now: now()) {
                                sendBuildStartedNotification(representativeBuild, soundEnabled)
                            }
                            newStartedWorkflows.insert(workflowId)
                        }
                    }
                }
            }

            // FAILURE: notification and/or failure sound, once each per workflow
            if let failedBuild = builds.first(where: { $0.buildStatus.isFailure }) {
                if notificationsEnabled && preferences.notifyOnFailure
                    && !appState.notifiedFailedWorkflows.contains(workflowId) {
                    if NotificationManager.isFresh(failedBuild.stateChangeDate, now: now()) {
                        sendBuildFailureNotification(failedBuild, soundEnabled)
                    }
                    newFailedWorkflows.insert(workflowId)
                }
                if preferences.playFailureSound
                    && (isProdBranch || isDeployedBranch)
                    && !appState.playedFailureSoundWorkflows.contains(workflowId) {
                    appState.playFailureSound()
                    newPlayedFailureSound.insert(workflowId)
                }
                newUnresolvedBaselineWorkflows.remove(workflowId)
            }

            // SUCCESS: notification and/or production-deploy confetti.
            // Uses v2 API to check ALL jobs (v1.1 may omit not-yet-started jobs).
            let suppressRecoveredBaseline = newUnresolvedBaselineWorkflows.contains(workflowId)
            let wantsSuccessNotification = notificationsEnabled && preferences.notifyOnSuccess
                && !appState.notifiedSuccessWorkflows.contains(workflowId)
            let deployEnv = DeployEnvironment.allCases.first { env in
                builds.contains { env.isDeploy($0, productionBranches: preferences.productionBranches) }
            }
            let celebrationKind: CelebrationKind? =
                (preferences.celebrateProdSuccess && isProdBranch) ? .production
                : (preferences.celebrateDeployedBranches && isDeployedBranch) ? .deploy(deployEnv ?? .devnet)
                : nil
            let wantsConfetti = celebrationKind != nil
                && !appState.celebratedSuccessWorkflows.contains(workflowId)
            if wantsSuccessNotification || wantsConfetti || suppressRecoveredBaseline {
                do {
                    let allJobs = try await fetchWorkflowJobs(workflowId)

                    guard !allJobs.isEmpty else { continue }

                    let hasIncompleteJobs = allJobs.contains { job in
                        let status = job.status
                        return status == "running" || status == "queued" ||
                               status == "blocked" || status == "not_run" ||
                               status == "on_hold"
                    }

                    if !hasIncompleteJobs,
                       allJobs.allSatisfy({ $0.status == "success" }),
                       let representativeBuild = builds.first {
                        if suppressRecoveredBaseline {
                            newSuccessWorkflows.insert(workflowId)
                            newCelebratedSuccess.insert(workflowId)
                        } else if wantsSuccessNotification {
                            if NotificationManager.isFresh(representativeBuild.stateChangeDate, now: now()) {
                                sendBuildSuccessNotification(representativeBuild, soundEnabled)
                            }
                            newSuccessWorkflows.insert(workflowId)
                        }
                        if wantsConfetti, !suppressRecoveredBaseline, let celebrationKind {
                            let label: String
                            let secondaryLabel: String?
                            if case .deploy = celebrationKind, let branch {
                                label = branch
                                secondaryLabel = representativeBuild.reponame ?? representativeBuild.projectSlug
                            } else {
                                label = representativeBuild.projectSlug
                                secondaryLabel = nil
                            }
                            appState.celebrate(projectLabel: label, secondaryLabel: secondaryLabel, kind: celebrationKind)
                            newCelebratedSuccess.insert(workflowId)
                            // One modal deploy = one celebration: consume the
                            // deployed-branch marker so later workflows on the same
                            // branch don't re-celebrate. Re-deploying re-arms it.
                            if case .deploy = celebrationKind, let branch {
                                appState.deployedBranchKeys.remove(
                                    AppState.deployKey(projectSlug: representativeBuild.projectSlug, branch: branch)
                                )
                            }
                        }
                    }
                    if suppressRecoveredBaseline {
                        newUnresolvedBaselineWorkflows.remove(workflowId)
                    }
                } catch {
                    // Ignore API errors, will retry on next poll
                }
            }
        }

        // Update tracked workflows
        appState.notifiedSuccessWorkflows = newSuccessWorkflows
        appState.notifiedFailedWorkflows = newFailedWorkflows
        appState.notifiedStartedWorkflows = newStartedWorkflows
        appState.celebratedSuccessWorkflows = newCelebratedSuccess
        appState.playedFailureSoundWorkflows = newPlayedFailureSound
        unresolvedBaselineWorkflowIds = newUnresolvedBaselineWorkflows

        // Check for new pending approvals
        if notificationsEnabled && preferences.notifyOnPendingApproval {
            for approval in currentApprovals {
                if !previousApprovals.contains(approval.id) {
                    sendPendingApprovalNotification(approval, soundEnabled)
                }
            }
        }
    }

    private nonisolated static func matchesCurrentUserFromCommit(
        build: Build,
        identities: Set<String>
    ) -> Bool {
        [build.committerEmail, build.committerName]
            .compactMap { $0?.lowercased() }
            .contains { identities.contains($0) }
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

                for job in jobs where job.isPendingApproval {
                    approvals.append(PendingApproval(workflowId: workflowId, job: job, build: build))
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
