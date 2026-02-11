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
    
    // MARK: - User Data
    var currentUser: User?
    var projects: [Project] = []
    var buildsByProject: [String: [Build]] = [:]
    var pendingApprovals: [PendingApproval] = []
    var notifiedApprovals: Set<String> = []
    var notifiedSuccessWorkflows: Set<String> = []
    var notifiedFailedWorkflows: Set<String> = []
    var notifiedStartedWorkflows: Set<String> = []

    // MARK: - Preferences
    var preferences: UserPreferences = .load()
    
    // MARK: - UI State
    var isLoading = false
    var error: String?
    var showingSettings = false
    
    // MARK: - Services
    let poller = BuildPoller()
    
    init() {
        poller.appState = self
    }
    
    // MARK: - Computed Properties
    
    var watchedProjects: [WatchedProject] {
        preferences.watchedProjects.filter { $0.isEnabled }
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
        
        for (_, builds) in buildsByProject {
            // Group by branch and check the most recent build per branch
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
        
        if hasRunning { return .running }
        if hasFailure { return .failing }
        if hasSuccess { return .passing }
        return .unknown
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
        await NotificationManager.shared.requestAuthorization()
        NotificationManager.shared.setupNotificationCategories()
        
        // Check for existing token
        if KeychainService.shared.hasToken() {
            await CircleCIAPI.shared.loadTokenFromKeychain()
            await validateAndLoadData()
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
    }
    
    func stopPolling() {
        poller.stopPolling()
    }
    
    func refreshNow() {
        poller.poll()
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
    
    func approveJob(_ approval: PendingApproval) async {
        do {
            try await CircleCIAPI.shared.approveJob(
                workflowId: approval.workflowId,
                approvalRequestId: approval.jobId
            )
            // Refresh after approval
            poller.poll()
        } catch {
            self.error = error.localizedDescription
        }
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
        // Note: watchedProjects is preserved
        currentScreen = .onboarding
    }
    
    func savePreferences() {
        preferences.save()
        // Restart polling with new interval
        if poller.isPolling {
            startPolling()
        }
    }
    
    // MARK: - Private
    
    private func validateAndLoadData() async {
        isLoading = true
        error = nil
        
        do {
            currentUser = try await CircleCIAPI.shared.validateToken()
            
            if preferences.watchedProjects.isEmpty {
                // First time - show project selection
                await loadProjects()
                currentScreen = .projectSelection
            } else {
                // Has projects - go to main
                currentScreen = .main
                startPolling()
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
            if preferences.watchedProjects.isEmpty {
                currentScreen = .onboarding
            } else {
                currentScreen = .main
                startPolling()
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
        case .passing: return "circle.fill"
        case .failing: return "circle.fill"
        case .running: return "circle.dotted"
        case .pendingApproval: return "pause.circle.fill"
        case .unknown: return "circle"
        }
    }
}
