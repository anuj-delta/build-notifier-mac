import Foundation
import SwiftUI

// MARK: - App State

enum AppScreen {
    case loading
    case onboarding
    case projectSelection
    case main
}

@MainActor
@Observable
final class AppState {
    // MARK: - Navigation
    var currentScreen: AppScreen = .loading
    
    // MARK: - User Data (CircleCI)
    var currentUser: User?
    var projects: [Project] = []
    var buildsByProject: [String: [Build]] = [:]
    var pendingApprovals: [PendingApproval] = []
    var workflowApprovalSupport: [String: Bool] = [:]
    var armedAutoApprovals: [String: ArmedAutoApproval] = [:]
    var notifiedApprovals: Set<String> = []
    var notifiedSuccessWorkflows: Set<String> = []
    var notifiedFailedWorkflows: Set<String> = []
    var notifiedStartedWorkflows: Set<String> = []

    // Celebration dedup (in-memory; seeded at baseline so relaunch doesn't re-fire)
    var celebratedSuccessWorkflows: Set<String> = []
    var playedFailureSoundWorkflows: Set<String> = []
    var celebratedVercelDeployments: Set<String> = []
    var playedFailureVercelDeployments: Set<String> = []

    // MARK: - User Data (Vercel)
    var vercelUser: VercelUserInfo?
    var vercelTeams: [VercelTeam] = []
    var vercelProjects: [VercelProject] = []
    var deploymentsByProject: [String: [VercelDeployment]] = [:]
    var notifiedVercelDeployments: Set<String> = []

    // MARK: - Preferences
    var preferences: UserPreferences = .load()
    
    // MARK: - UI State
    var isLoading = false
    var error: String?
    var showingSettings = false
    var availableUpdate: ReleaseInfo?
    
    // MARK: - Services
    let poller: BuildPoller
    let vercelPoller: VercelPoller
    let autoApprovalPoller: AutoApprovalPoller
    
    init(
        poller: BuildPoller? = nil,
        vercelPoller: VercelPoller? = nil,
        autoApprovalPoller: AutoApprovalPoller? = nil
    ) {
        self.poller = poller ?? BuildPoller()
        self.vercelPoller = vercelPoller ?? VercelPoller()
        self.autoApprovalPoller = autoApprovalPoller ?? AutoApprovalPoller()
        self.poller.appState = self
        self.vercelPoller.appState = self
        self.autoApprovalPoller.appState = self
    }
    
    // MARK: - Computed Properties
    
    var watchedProjects: [WatchedProject] {
        preferences.watchedProjects.filter { $0.isEnabled }
    }
    
    var watchedVercelProjects: [WatchedVercelProject] {
        preferences.watchedVercelProjects.filter { $0.isEnabled }
    }

    var armedAutoApprovalWorkflowIds: Set<String> {
        Set(armedAutoApprovals.keys)
    }

    var approvalCapableWorkflowIds: Set<String> {
        Set(workflowApprovalSupport.compactMap { workflowId, supportsApproval in
            supportsApproval ? workflowId : nil
        })
    }
    
    var hasCircleCIToken: Bool {
        KeychainService.shared.hasToken()
    }
    
    var hasVercelToken: Bool {
        KeychainService.shared.hasVercelToken()
    }
    
    var hasAnyIntegration: Bool {
        hasCircleCIToken || hasVercelToken
    }
    
    var overallStatus: OverallStatus {
        // Check for pending approvals first
        if !pendingApprovals.isEmpty {
            return .pendingApproval
        }
        
        // Check builds - look at the LATEST build per branch per project
        var hasRunning = false
        var hasFailure = false
        var hasSuccess = false
        
        // CircleCI builds
        for (_, builds) in buildsByProject {
            var branchLatest: [String: Build] = [:]
            for build in builds {
                let branch = build.branch ?? "unknown"
                if branchLatest[branch] == nil || build.buildNum > (branchLatest[branch]?.buildNum ?? 0) {
                    branchLatest[branch] = build
                }
            }
            
            for (_, build) in branchLatest {
                let status = build.buildStatus
                if status.isRunning { hasRunning = true }
                if status.isFailure { hasFailure = true }
                if status.isSuccess { hasSuccess = true }
            }
        }
        
        // Vercel deployments
        for (_, deployments) in deploymentsByProject {
            if let latest = deployments.first {
                let status = latest.deploymentStatus
                if status.isRunning { hasRunning = true }
                if status.isFailure { hasFailure = true }
                if status.isSuccess { hasSuccess = true }
            }
        }
        
        if hasFailure { return .failing }
        if hasRunning { return .running }
        if hasSuccess { return .passing }
        return .unknown
    }

    var hasActiveBuildActivity: Bool {
        for (_, builds) in buildsByProject {
            if builds.contains(where: { $0.buildStatus.isRunning }) {
                return true
            }
        }

        for (_, deployments) in deploymentsByProject {
            if deployments.contains(where: { $0.deploymentStatus.isRunning }) {
                return true
            }
        }

        return false
    }
    
    var groupedBuilds: [(project: WatchedProject, builds: [String: [Build]])] {
        var result: [(project: WatchedProject, builds: [String: [Build]])] = []
        
        for project in watchedProjects {
            guard let builds = buildsByProject[project.slug] else { continue }
            
            // Group builds by branch
            var buildsByBranch: [String: [Build]] = [:]
            for build in builds {
                let branch = build.branch ?? "unknown"
                buildsByBranch[branch, default: []].append(build)
            }
            
            // Sort branches: main/master first, then alphabetically
            let sortedBranches = buildsByBranch.keys.sorted { b1, b2 in
                let mainBranches = ["main", "master", "develop"]
                let b1Priority = mainBranches.firstIndex(of: b1) ?? Int.max
                let b2Priority = mainBranches.firstIndex(of: b2) ?? Int.max
                if b1Priority != b2Priority {
                    return b1Priority < b2Priority
                }
                return b1 < b2
            }
            
            var sortedBuildsByBranch: [String: [Build]] = [:]
            for branch in sortedBranches {
                if let branchBuilds = buildsByBranch[branch] {
                    // Keep only the most recent build per branch
                    sortedBuildsByBranch[branch] = Array(branchBuilds.prefix(1))
                }
            }
            
            result.append((project: project, builds: sortedBuildsByBranch))
        }
        
        // Sort projects by recent activity (latest build timestamp), then name.
        return result.sorted { lhs, rhs in
            let lhsLatest = buildsByProject[lhs.project.slug]?.compactMap { $0.activityDate }.max()
            let rhsLatest = buildsByProject[rhs.project.slug]?.compactMap { $0.activityDate }.max()
            
            switch (lhsLatest, rhsLatest) {
            case let (l?, r?):
                if l != r { return l > r }
                return lhs.project.displayName.lowercased() < rhs.project.displayName.lowercased()
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.project.displayName.lowercased() < rhs.project.displayName.lowercased()
            }
        }
    }
    
    // MARK: - Actions
    
    func initialize() async {
        workflowApprovalSupport.removeAll()
        armedAutoApprovals.removeAll()
        await NotificationManager.shared.requestAuthorization()
        NotificationManager.shared.setupNotificationCategories()

        Task { await checkForUpdates() }
        
        // Load Vercel token if available
        if KeychainService.shared.hasVercelToken() {
            await VercelAPI.shared.loadTokenFromKeychain()
            await restoreVercelSession()
        }
        
        // Check for existing CircleCI token
        if KeychainService.shared.hasToken() {
            await CircleCIAPI.shared.loadTokenFromKeychain()
            await validateAndLoadData()
        } else if KeychainService.shared.hasVercelToken() {
            // Vercel only - go to main
            currentScreen = .main
            startVercelPolling()
        } else {
            currentScreen = .onboarding
        }
    }
    
    func validateToken(_ token: String) async -> Bool {
        isLoading = true
        error = nil
        
        do {
            await CircleCIAPI.shared.setToken(token)
            currentUser = try await CircleCIAPI.shared.validateToken()
            try KeychainService.shared.saveToken(token)
            isLoading = false
            return true
        } catch {
            self.error = error.localizedDescription
            await CircleCIAPI.shared.clearToken()
            isLoading = false
            return false
        }
    }
    
    func loadProjects() async {
        isLoading = true
        error = nil
        
        do {
            projects = try await CircleCIAPI.shared.getProjects()
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
    
    func addToWatchlist(_ project: Project, followMode: FollowMode = .all) {
        let watchedProject = WatchedProject(from: project, followMode: followMode)
        if !preferences.watchedProjects.contains(where: { $0.id == watchedProject.id }) {
            preferences.watchedProjects.append(watchedProject)
            preferences.save()
        }
    }
    
    func removeFromWatchlist(_ project: WatchedProject) {
        preferences.watchedProjects.removeAll { $0.id == project.id }
        preferences.save()
    }
    
    func updateWatchedProject(_ project: WatchedProject) {
        if let index = preferences.watchedProjects.firstIndex(where: { $0.id == project.id }) {
            preferences.watchedProjects[index] = project
            preferences.save()
        }
    }
    
    func startPolling() {
        poller.startPolling(interval: TimeInterval(preferences.pollingIntervalSeconds))
        autoApprovalPoller.startPolling(interval: 120)
    }
    
    func stopPolling() {
        poller.stopPolling()
        autoApprovalPoller.stopPolling()
    }
    
    func startVercelPolling() {
        vercelPoller.startPolling(interval: TimeInterval(preferences.pollingIntervalSeconds))
    }
    
    func stopVercelPolling() {
        vercelPoller.stopPolling()
    }
    
    func startAllPolling() {
        if hasCircleCIToken && !preferences.watchedProjects.isEmpty {
            startPolling()
        }
        if hasVercelToken && !preferences.watchedVercelProjects.isEmpty {
            startVercelPolling()
        }
    }
    
    func stopAllPolling() {
        stopPolling()
        stopVercelPolling()
    }
    
    func refreshNow() {
        // Popover open is the reliable interaction point for an .accessory app,
        // so recover notification-permission state here too.
        Task {
            await NotificationManager.shared.checkAuthorizationStatus()
        }
        if hasCircleCIToken {
            poller.poll()
            autoApprovalPoller.poll()
        }
        if hasVercelToken {
            vercelPoller.poll()
        }
        Task { await checkForUpdates() }
    }

    func checkForUpdates() async {
        availableUpdate = await UpdateChecker.shared.checkForUpdate()
    }

    // MARK: - Celebrations

    func celebrateProdSuccess(projectLabel: String) {
        guard preferences.celebrateProdSuccess else { return }
        AudioPlayer.shared.play(CelebrationSound(rawValue: preferences.successSound) ?? .defaultSuccess)
        ConfettiPresenter.shared.present(projectLabel: projectLabel)
    }

    func playFailureSound() {
        guard preferences.playFailureSound else { return }
        AudioPlayer.shared.play(CelebrationSound(rawValue: preferences.failureSound) ?? .defaultFailure)
    }
    
    func retryBuild(_ build: Build) async {
        guard let username = build.username, let reponame = build.reponame else { return }
        
        do {
            _ = try await CircleCIAPI.shared.retryBuild(
                vcsType: build.vcsType,
                orgName: username,
                repoName: reponame,
                buildNum: build.buildNum
            )
            // Refresh after retry
            poller.poll()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func cancelBuild(_ build: Build) async {
        guard let username = build.username, let reponame = build.reponame else { return }
        
        do {
            _ = try await CircleCIAPI.shared.cancelBuild(
                vcsType: build.vcsType,
                orgName: username,
                repoName: reponame,
                buildNum: build.buildNum
            )
            // Refresh after cancel
            poller.poll()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func triggerDeployment(project: WatchedProject, branch: String, env: String) async throws -> TriggeredPipeline {
        let params = env.isEmpty ? nil : ["env": env]
        let pipeline = try await CircleCIAPI.shared.triggerPipeline(
            vcsType: project.vcsType,
            orgName: project.orgName,
            repoName: project.repoName,
            branch: branch,
            parameters: params
        )
        schedulePostTriggerRefresh()
        return pipeline
    }

    /// Delays (seconds) for the follow-up polls after a trigger. Overridable in tests.
    var postTriggerRefreshDelays: [TimeInterval] = [2, 4, 6]

    /// A freshly triggered pipeline takes a few seconds to appear in the v1.1
    /// builds API, so poll immediately and then a couple more times to catch it
    /// without waiting for the next full polling interval.
    func schedulePostTriggerRefresh() {
        poller.poll()
        Task { @MainActor [weak self] in
            guard let delays = self?.postTriggerRefreshDelays else { return }
            for delaySeconds in delays {
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                guard let self else { return }
                await self.poller.checkNow()
            }
        }
    }

    func approveJob(_ approval: PendingApproval) async {
        do {
            try await CircleCIAPI.shared.approveJob(
                workflowId: approval.workflowId,
                approvalRequestId: approval.jobId
            )
            armedAutoApprovals.removeValue(forKey: approval.workflowId)
            // Refresh after approval
            poller.poll()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func recordWorkflowApprovalSupport(workflowId: String, jobs: [WorkflowJob]) {
        workflowApprovalSupport[workflowId] = jobs.contains(where: \.canStillRequireApproval)
    }

    func mergeWorkflowApprovalSupport(_ supportByWorkflowId: [String: Bool]) {
        workflowApprovalSupport.merge(supportByWorkflowId) { _, new in new }
    }

    func canAutoApprove(_ build: Build) -> Bool {
        guard !build.buildStatus.isTerminal,
              let workflowId = build.workflows?.workflowId else {
            return false
        }

        return workflowApprovalSupport[workflowId] == true
    }

    func armAutoApprove(for build: Build) {
        guard canAutoApprove(build),
              let armedApproval = ArmedAutoApproval(build: build) else {
            return
        }
        armedAutoApprovals[armedApproval.workflowId] = armedApproval
        autoApprovalPoller.poll()
    }

    func cancelAutoApprove(forWorkflowId workflowId: String) {
        armedAutoApprovals.removeValue(forKey: workflowId)
    }
    
    func signOut() {
        stopPolling()
        try? KeychainService.shared.deleteToken()
        Task {
            await CircleCIAPI.shared.clearToken()
        }
        currentUser = nil
        projects = []
        buildsByProject = [:]
        pendingApprovals = []
        workflowApprovalSupport = [:]
        armedAutoApprovals = [:]
        preferences.watchedProjects = []
        preferences.save()
        currentScreen = .onboarding
    }
    
    func changeToken() {
        // Preserve watchlist but clear token and go to onboarding
        stopPolling()
        try? KeychainService.shared.deleteToken()
        Task {
            await CircleCIAPI.shared.clearToken()
        }
        currentUser = nil
        projects = []
        buildsByProject = [:]
        pendingApprovals = []
        workflowApprovalSupport = [:]
        armedAutoApprovals = [:]
        // Note: watchedProjects is preserved
        currentScreen = .onboarding
    }
    
    func savePreferences() {
        preferences.save()
        // Restart polling with new interval
        if poller.isPolling || vercelPoller.isPolling {
            startAllPolling()
        }
    }
    
    // MARK: - Vercel Actions
    
    func validateVercelToken(_ token: String) async -> Bool {
        isLoading = true
        error = nil
        
        do {
            await VercelAPI.shared.setToken(token)
            let response = try await VercelAPI.shared.validateToken()
            vercelUser = response.user
            try KeychainService.shared.saveVercelToken(token)
            isLoading = false
            return true
        } catch {
            self.error = error.localizedDescription
            await VercelAPI.shared.clearToken()
            isLoading = false
            return false
        }
    }
    
    func loadVercelTeams() async {
        isLoading = true
        error = nil
        
        do {
            vercelTeams = try await VercelAPI.shared.getTeams()
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
    
    func loadVercelProjects(teamId: String?) async {
        isLoading = true
        error = nil
        
        do {
            vercelProjects = try await VercelAPI.shared.getProjects(teamId: teamId)
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
    
    func addVercelToWatchlist(_ project: VercelProject, teamId: String?, followMode: FollowMode = .all) {
        let watchedProject = WatchedVercelProject(from: project, teamId: teamId, followMode: followMode)
        if let index = preferences.watchedVercelProjects.firstIndex(where: { $0.id == watchedProject.id }) {
            preferences.watchedVercelProjects[index] = watchedProject
            preferences.save()
        } else {
            preferences.watchedVercelProjects.append(watchedProject)
            preferences.save()
        }
    }
    
    func removeVercelFromWatchlist(_ project: WatchedVercelProject) {
        preferences.watchedVercelProjects.removeAll { $0.id == project.id }
        preferences.save()
    }
    
    func updateWatchedVercelProject(_ project: WatchedVercelProject) {
        if let index = preferences.watchedVercelProjects.firstIndex(where: { $0.id == project.id }) {
            preferences.watchedVercelProjects[index] = project
            preferences.save()
        }
    }
    
    func disconnectVercel() {
        stopVercelPolling()
        try? KeychainService.shared.deleteVercelToken()
        Task {
            await VercelAPI.shared.clearToken()
        }
        vercelUser = nil
        vercelTeams = []
        vercelProjects = []
        deploymentsByProject = [:]
        preferences.watchedVercelProjects = []
        preferences.selectedVercelTeamId = nil
        preferences.save()
    }
    
    // MARK: - Private
    
    private func restoreVercelSession() async {
        do {
            let response = try await VercelAPI.shared.validateToken()
            vercelUser = response.user
        } catch {
            // Keep the saved token for now; account details can be refreshed later.
            vercelUser = nil
        }
    }
    
    private func validateAndLoadData() async {
        isLoading = true
        error = nil
        
        do {
            currentUser = try await CircleCIAPI.shared.validateToken()
            
            if preferences.watchedProjects.isEmpty && preferences.watchedVercelProjects.isEmpty {
                // First time - show project selection
                await loadProjects()
                currentScreen = .projectSelection
            } else {
                // Has projects - go to main
                currentScreen = .main
                startAllPolling()
            }
        } catch {
            self.error = error.localizedDescription
            
            // Only wipe credentials when token is actually invalid.
            if let circleError = error as? CircleCIError, case .unauthorized = circleError {
                try? KeychainService.shared.deleteToken()
                await CircleCIAPI.shared.clearToken()
                currentScreen = .onboarding
                isLoading = false
                return
            }
            
            // Transient error (RBAC/403, offline, rate limits, etc). Keep token.
            if preferences.watchedProjects.isEmpty && preferences.watchedVercelProjects.isEmpty {
                currentScreen = .onboarding
            } else {
                currentScreen = .main
                startAllPolling()
            }
        }
        
        isLoading = false
    }
    
    func retryStartup() {
        Task {
            await validateAndLoadData()
        }
    }
}

// MARK: - Overall Status

enum OverallStatus {
    case passing
    case failing
    case running
    case pendingApproval
    case unknown

    var title: String {
        switch self {
        case .passing: return "All clear"
        case .failing: return "Needs attention"
        case .running: return "Actively building"
        case .pendingApproval: return "Approval waiting"
        case .unknown: return "Waiting for updates"
        }
    }
    
    var iconName: String {
        switch self {
        case .passing: return "checkmark.circle.fill"
        case .failing: return "xmark.circle.fill"
        case .running: return "arrow.triangle.2.circlepath"
        case .pendingApproval: return "pause.circle.fill"
        case .unknown: return "circle"
        }
    }
    
    var color: Color {
        switch self {
        case .passing: return .green
        case .failing: return .red
        case .running: return .yellow
        case .pendingApproval: return .orange
        case .unknown: return .gray
        }
    }
    
    var menuBarIcon: String {
        switch self {
        case .passing: return "checkmark.circle.fill"
        case .failing: return "exclamationmark.circle.fill"
        case .running: return "arrow.triangle.2.circlepath.circle.fill"
        case .pendingApproval: return "pause.circle.fill"
        case .unknown: return "circle.dashed"
        }
    }
}
