import Foundation
import Combine

// MARK: - Build Poller

@MainActor
final class BuildPoller: ObservableObject {
    @Published private(set) var isPolling = false
    @Published private(set) var lastPollTime: Date?
    @Published private(set) var error: Error?
    
    private var timer: Timer?
    private var pollTask: Task<Void, Never>?
    
    weak var appState: AppState?
    
    init() {}
    
    // MARK: - Start/Stop Polling
    
    func startPolling(interval: TimeInterval = 60) {
        stopPolling()
        
        isPolling = true
        
        // Poll immediately
        poll()
        
        // Then poll on interval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
    }
    
    func stopPolling() {
        timer?.invalidate()
        timer = nil
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }
    
    func poll() {
        pollTask?.cancel()
        pollTask = Task {
            await performPoll()
        }
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
        
        // Fetch builds for each watched project
        var newBuildsByProject: [String: [Build]] = [:]
        var newPendingApprovals: [PendingApproval] = []
        
        await withTaskGroup(of: (String, [Build], [PendingApproval])?.self) { group in
            for project in watchedProjects {
                group.addTask {
                    do {
                        var builds = try await CircleCIAPI.shared.getBuilds(
                            vcsType: project.vcsType,
                            orgName: project.orgName,
                            repoName: project.repoName,
                            limit: 30
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
                                let jobs = try await CircleCIAPI.shared.getWorkflowJobs(workflowId: workflowId)

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
                        
                        return (project.slug, builds, approvals)
                    } catch {
                        return nil
                    }
                }
            }
            
            for await result in group {
                if let (slug, builds, approvals) = result {
                    newBuildsByProject[slug] = builds
                    newPendingApprovals.append(contentsOf: approvals)
                }
            }
        }
        
        // Update state
        appState.buildsByProject = newBuildsByProject
        appState.pendingApprovals = newPendingApprovals
        lastPollTime = Date()
        
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
