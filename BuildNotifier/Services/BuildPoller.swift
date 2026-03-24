import Foundation
import Combine

// MARK: - Build Poller

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
    
    weak var appState: AppState?
    
    init(
        fetchBuilds: ((String, String, String, Int) async throws -> [Build])? = nil,
        fetchWorkflowJobs: ((String) async throws -> [WorkflowJob])? = nil
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
        
        // Fetch builds for each watched project
        var newBuildsByProject: [String: [Build]] = [:]
        var newPendingApprovals: [PendingApproval] = []
        var workflowApprovalSupport: [String: Bool] = [:]

        await withTaskGroup(of: (String, [Build], [PendingApproval], [String: Bool])?.self) { group in
            for project in watchedProjects {
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
                            builds = builds.filter { build in
                                // Match by email (most reliable)
                                if let email = currentUserEmail, let committerEmail = build.committerEmail {
                                    if committerEmail.lowercased() == email.lowercased() {
                                        return true
                                    }
                                }
                                // Match by name
                                if let name = currentUserName, let committerName = build.committerName {
                                    if committerName.lowercased() == name.lowercased() {
                                        return true
                                    }
                                }
                                // Match by login (fallback)
                                if let login = currentUserLogin, let committerName = build.committerName {
                                    if committerName.lowercased() == login.lowercased() {
                                        return true
                                    }
                                }
                                return false
                            }
                        }
                        
                        // Check for pending approvals
                        // Dedupe by workflow ID to avoid redundant API calls
                        var approvals: [PendingApproval] = []
                        var approvalSupport: [String: Bool] = [:]
                        var checkedWorkflowIds = Set<String>()

                        // Check all unique workflows from recent builds (limit to avoid rate limits)
                        // Include any workflow that might have pending approvals
                        let recentBuilds = builds.prefix(20)

                        for build in recentBuilds {
                            guard let workflowId = build.workflows?.workflowId,
                                  !checkedWorkflowIds.contains(workflowId) else {
                                continue
                            }
                            checkedWorkflowIds.insert(workflowId)
                            
                            do {
                                let jobs = try await fetchWorkflowJobs(workflowId)
                                approvalSupport[workflowId] = jobs.contains(where: \.isApprovalJob)

                                // Check if any non-approval jobs are still in progress
                                // (running, queued, or blocked waiting for something other than approval)
                                let hasInProgressJobs = jobs.contains { job in
                                    !job.isApprovalJob && (job.status == "running" || job.status == "queued")
                                }

                                // Only consider approvals as "pending" when workflow is fully blocked
                                // (no jobs running/queued, only the approval is holding things up)
                                if !hasInProgressJobs {
                                    let pendingJobs = jobs.filter { $0.isPendingApproval }
                                    for job in pendingJobs {
                                        approvals.append(PendingApproval(workflowId: workflowId, job: job, build: build))
                                    }
                                }
                            } catch {
                                // Ignore workflow job errors
                            }
                        }
                        
                        return (project.slug, builds, approvals, approvalSupport)
                    } catch {
                        return nil
                    }
                }
            }
            
            for await result in group {
                if let (slug, builds, approvals, approvalSupport) = result {
                    newBuildsByProject[slug] = builds
                    newPendingApprovals.append(contentsOf: approvals)
                    workflowApprovalSupport.merge(approvalSupport) { _, new in new }
                }
            }
        }
        
        // Update state
        appState.buildsByProject = newBuildsByProject
        appState.pendingApprovals = newPendingApprovals
        appState.mergeWorkflowApprovalSupport(workflowApprovalSupport)
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

        let notificationManager = NotificationManager.shared
        let soundEnabled = preferences.notificationSoundEnabled

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
                            notificationManager.sendBuildStartedNotification(build: representativeBuild, soundEnabled: soundEnabled)
                            newStartedWorkflows.insert(workflowId)
                        }
                    }
                }
            }

            // FAILURE: Notify once when ANY job in workflow fails
            if preferences.notifyOnFailure {
                if !appState.notifiedFailedWorkflows.contains(workflowId) {
                    if let failedBuild = builds.first(where: { $0.buildStatus.isFailure }) {
                        notificationManager.sendBuildFailureNotification(build: failedBuild, soundEnabled: soundEnabled)
                        newFailedWorkflows.insert(workflowId)
                    }
                }
            }

            // SUCCESS: Notify once when ALL jobs in workflow succeed
            // Use v2 API to check ALL jobs (v1.1 may not include not-yet-started jobs)
            if preferences.notifyOnSuccess {
                if !appState.notifiedSuccessWorkflows.contains(workflowId) {
                    do {
                        let allJobs = try await CircleCIAPI.shared.getWorkflowJobs(workflowId: workflowId)

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
                                notificationManager.sendBuildSuccessNotification(build: representativeBuild, soundEnabled: soundEnabled)
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
                    notificationManager.sendPendingApprovalNotification(approval: approval, soundEnabled: soundEnabled)
                }
            }
        }
    }
}
