import Foundation
import SwiftUI

// MARK: - App State

enum AppScreen {
    case loading
    case onboarding
    case projectSelection
    case main
}

/// Aggregate build/deployment tallies across all watched projects.
struct StatusCounts {
    var running = 0
    var failing = 0
    var passing = 0

    /// Bucket one build/deploy by its terminal-ish state. Failure/running/success
    /// are mutually exclusive per unit, so at most one bucket increments.
    mutating func tally(isFailure: Bool, isRunning: Bool, isSuccess: Bool) {
        if isFailure { failing += 1 }
        else if isRunning { running += 1 }
        else if isSuccess { passing += 1 }
    }

    /// Priority order for the menu bar: pending approval > running > failing >
    /// passing > unknown. Running outranks failing so an active build shows the
    /// animated "building" icon rather than being masked by a stale failure.
    /// Callers pass the pending-approval count separately since it isn't part of
    /// the build/deploy tally.
    func overallStatus(pendingApprovals: Int) -> OverallStatus {
        if pendingApprovals > 0 { return .pendingApproval }
        if running > 0 { return .running }
        if failing > 0 { return .failing }
        if passing > 0 { return .passing }
        return .unknown
    }
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

    // Branches the user deployed via the Deploy-a-Branch modal this session.
    // Their success fires confetti and their failure plays the failure sound,
    // even when the branch isn't in `productionBranches`. Cleared on relaunch.
    var deployedBranchKeys: Set<String> = []
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
    
    /// Single pass over watched builds/deployments producing the counts the menu
    /// bar needs. Uses the latest build per branch per project (and the latest
    /// deployment per project) as the counted unit — the same unit overallStatus
    /// reasons about. A build's status is one value, so the buckets are mutually
    /// exclusive per unit.
    var statusCounts: StatusCounts {
        var counts = StatusCounts()
        let keys = keyBranches
        let now = Date()

        for (_, builds) in buildsByProject {
            // Latest build per branch (build numbers are monotonic within a branch).
            var branchLatest: [String: Build] = [:]
            for build in builds {
                let branch = build.branch ?? "unknown"
                if branchLatest[branch].map({ build.buildNum > $0.buildNum }) ?? true {
                    branchLatest[branch] = build
                }
            }

            // Parse each branch's activity date once - it's reused by both the
            // recency-ranked sort and the staleness check below, and parsing isn't
            // free on the per-redraw hot path.
            let dateByBranch = branchLatest.compactMapValues { $0.activityDate }

            // Visible set: the most-recently-active branches, same as the popover.
            let visible = Set(
                branchLatest.keys
                    .sorted { (dateByBranch[$0] ?? .distantPast) > (dateByBranch[$1] ?? .distantPast) }
                    .prefix(Self.maxBranchesPerProject)
            )

            for (branch, build) in branchLatest {
                // A key branch (main/develop/production) always counts. Any other
                // branch counts only while it's both visible and not stale, so
                // abandoned feature branches stop pinning the badge to "failing".
                if !keys.contains(branch) {
                    guard visible.contains(branch) else { continue }
                    if let date = dateByBranch[branch],
                       now.timeIntervalSince(date) > Self.statusRecencyWindow { continue }
                }
                let status = build.buildStatus
                counts.tally(isFailure: status.isFailure, isRunning: status.isRunning, isSuccess: status.isSuccess)
            }
        }

        for (_, deployments) in deploymentsByProject {
            guard let deploy = deployments.first else { continue }
            // Production deploys always count; previews only while recent.
            if !deploy.isProduction,
               now.timeIntervalSince(deploy.createdDate) > Self.statusRecencyWindow { continue }
            let status = deploy.deploymentStatus
            counts.tally(isFailure: status.isFailure, isRunning: status.isRunning, isSuccess: status.isSuccess)
        }

        return counts
    }

    /// Non-key branches older than this stop counting toward the menu bar status,
    /// so an abandoned branch whose last build failed doesn't pin the badge.
    private static let statusRecencyWindow: TimeInterval = 7 * 24 * 60 * 60

    /// Branches that always count toward the menu bar status, even when stale or
    /// crowded out of the visible list - the ones you always want to know about.
    private var keyBranches: Set<String> {
        Set(preferences.productionBranches + ["develop"])
    }

    var overallStatus: OverallStatus {
        statusCounts.overallStatus(pendingApprovals: pendingApprovals.count)
    }

    /// A deploy to any tracked environment is in flight (its workflow is still
    /// running/on-hold). Drives the dedicated deploying glyph in the menu bar.
    var isDeploying: Bool {
        deployingBranchBySlugByEnv.values.contains { !$0.isEmpty }
    }

    /// Rotation phase (0..<1) for the animated menu bar spinner. `MenuBarExtra`
    /// only re-renders its label - and thus redraws the status item - when a
    /// tracked observable input changes, not on the label's own `@State` or a
    /// `TimelineView`. So a timer advances this observable phase and the label
    /// reads it, which is the same path that swaps the idle/spinner/approval icon.
    var deploySpinnerPhase: Double = 0
    private var deploySpinnerTimer: Timer?
    private var deploySpinnerStart: TimeInterval = 0
    private let deploySpinnerFPS: Double = 60
    private let deploySpinnerPeriod: Double = 0.9

    /// Menu-bar status snapshot, recomputed once per poll in `refreshDeploySpinner`
    /// rather than by the label. `overallStatus`/`statusCounts` parse ISO8601 build
    /// timestamps (~1.5ms per pass), so recomputing them on every 60fps redraw while
    /// the spinner animates would burn ~9% of a core; the label reads these cached
    /// values instead and the animation path does no parsing.
    private(set) var menuBarCounts = StatusCounts()
    private(set) var menuBarStatus: OverallStatus = .unknown

    /// Recompute the cached menu-bar status and start/stop the spinner timer to
    /// match it. Called by each poller right after it updates build/deploy state.
    func refreshDeploySpinner() {
        menuBarCounts = statusCounts
        menuBarStatus = menuBarCounts.overallStatus(pendingApprovals: pendingApprovals.count)

        if menuBarStatus == .running {
            guard deploySpinnerTimer == nil else { return }
            // Derive the phase from elapsed monotonic time rather than accumulating
            // a fixed step per tick, so a late or dropped frame snaps to the right
            // angle instead of slowing the spin - the rotation stays at a constant
            // velocity and reads smoothly even if the timer jitters.
            deploySpinnerStart = ProcessInfo.processInfo.systemUptime
            let timer = Timer(timeInterval: 1.0 / deploySpinnerFPS, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let elapsed = ProcessInfo.processInfo.systemUptime - self.deploySpinnerStart
                    self.deploySpinnerPhase = (elapsed / self.deploySpinnerPeriod)
                        .truncatingRemainder(dividingBy: 1)
                }
            }
            timer.tolerance = 0
            RunLoop.main.add(timer, forMode: .common)
            deploySpinnerTimer = timer
        } else {
            deploySpinnerTimer?.invalidate()
            deploySpinnerTimer = nil
            deploySpinnerPhase = 0
        }
    }

    static let maxBranchesPerProject = 5

    /// Branches to show per project, newest first, each with the build to display.
    /// Stored rather than computed: the menu rebuilds this on every redraw otherwise,
    /// including on every keystroke in its search field.
    private(set) var groupedBuilds: [ProjectBuilds] = []

    func regroupBuilds() {
        var result: [(group: ProjectBuilds, latest: Date)] = []

        for project in watchedProjects {
            guard let builds = buildsByProject[project.slug] else { continue }

            var buildsByBranch: [String: [Build]] = [:]
            for build in builds {
                let branch = build.branch ?? "unknown"
                buildsByBranch[branch, default: []].append(build)
            }

            // Keep the most recently active branches so feature branches surface
            // alongside main/develop instead of being crowded out. Rank and pick
            // by activityDate rather than trusting the API's response order, so the
            // right branch/build wins even if buildsByProject is ever reordered.
            let latestByBranch = buildsByBranch.mapValues { builds in
                builds.compactMap(\.activityDate).max() ?? .distantPast
            }
            let branchesByRecency = buildsByBranch.keys.sorted { b1, b2 in
                let d1 = latestByBranch[b1] ?? .distantPast
                let d2 = latestByBranch[b2] ?? .distantPast
                if d1 != d2 { return d1 > d2 }
                return b1 < b2
            }

            // A branch live (or mid-deploy) on any environment must always show, even when it
            // is older than the top-N by recency - otherwise a long-lived deploy branch (e.g.
            // the one pinned to sigma) silently drops off the list and its badge never renders.
            var deployedBranches: Set<String> = []
            for env in DeployEnvironment.allCases {
                if let branch = deployedBranchBySlugByEnv[env]?[project.slug] { deployedBranches.insert(branch) }
                if let branch = deployingBranchBySlugByEnv[env]?[project.slug] { deployedBranches.insert(branch) }
            }

            var selectedBranches = Array(branchesByRecency.prefix(Self.maxBranchesPerProject))
            for branch in branchesByRecency where deployedBranches.contains(branch) && !selectedBranches.contains(branch) {
                selectedBranches.append(branch)
            }

            let branches: [BranchBuild] = selectedBranches.compactMap { branch in
                guard let jobs = buildsByBranch[branch],
                      let latest = jobs.max(by: {
                          ($0.activityDate ?? .distantPast) < ($1.activityDate ?? .distantPast)
                      }) else { return nil }
                return BranchBuild(
                    branch: branch,
                    build: latest,
                    span: WorkflowSpan(jobs: siblings(of: latest, in: jobs))
                )
            }

            result.append((
                group: ProjectBuilds(project: project, branches: branches),
                latest: latestByBranch.values.max() ?? .distantPast
            ))
        }

        // Sort projects by recent activity (latest build timestamp), then name.
        groupedBuilds = result
            .sorted { lhs, rhs in
                if lhs.latest != rhs.latest { return lhs.latest > rhs.latest }
                return lhs.group.project.displayName.lowercased() < rhs.group.project.displayName.lowercased()
            }
            .map(\.group)
    }

    /// The other jobs of `build`'s workflow. A build with no workflow id stands alone rather
    /// than matching every other id-less build on the branch.
    private func siblings(of build: Build, in jobs: [Build]) -> [Build] {
        guard let id = build.workflows?.workflowId else { return [build] }
        return jobs.filter { $0.workflows?.workflowId == id }
    }

    /// The branch currently live on each deploy environment per project, resolved during
    /// polling from the authoritative v2 workflow rollup status (the same status CircleCI's
    /// own pipeline list shows). Keyed by environment, then project slug. Populated by
    /// `BuildPoller`.
    var deployedBranchBySlugByEnv: [DeployEnvironment: [String: String]] = [:]

    /// The branch with an in-flight deploy to each environment per project (its deploy
    /// workflow is still running/on-hold, not yet terminal). Keyed by environment, then
    /// project slug. Replaced every poll so a finished or failed deploy clears immediately -
    /// on failure the row falls back to whatever `deployedBranchBySlugByEnv` still holds.
    var deployingBranchBySlugByEnv: [DeployEnvironment: [String: String]] = [:]

    /// v2 workflow rollup status keyed by workflow id, for the workflows backing the rows
    /// currently on screen. Populated by `BuildPoller`. Rows trust this over the v1.1 build
    /// status because v1.1 lags v2 (and CircleCI's own UI): a finished workflow can keep
    /// reporting a running job for a short window, which otherwise leaves the row spinning.
    var workflowStatusByWorkflowId: [String: String] = [:]

    /// The branch currently live on `env` for a project: the branch of the most recent deploy
    /// to that environment whose whole workflow succeeded. v1.1 alone can't tell a still-pending
    /// deploy from a finished one (it omits `not_run` jobs), so the completed-success check
    /// runs against the v2 workflow status in `BuildPoller` and the result is cached here.
    func deployedBranch(forSlug slug: String, env: DeployEnvironment) -> String? {
        deployedBranchBySlugByEnv[env]?[slug]
    }

    /// The branch live on each environment for a project, for the environments that have one.
    func deployedBranchesByEnv(forSlug slug: String) -> [DeployEnvironment: String] {
        var result: [DeployEnvironment: String] = [:]
        for env in DeployEnvironment.allCases {
            if let branch = deployedBranchBySlugByEnv[env]?[slug] {
                result[env] = branch
            }
        }
        return result
    }

    /// The branch mid-deploy to `env` for a project, if any.
    func deployingBranch(forSlug slug: String, env: DeployEnvironment) -> String? {
        deployingBranchBySlugByEnv[env]?[slug]
    }

    /// The branch mid-deploy to each environment for a project, for the environments that have one.
    func deployingBranchesByEnv(forSlug slug: String) -> [DeployEnvironment: String] {
        var result: [DeployEnvironment: String] = [:]
        for env in DeployEnvironment.allCases {
            if let branch = deployingBranchBySlugByEnv[env]?[slug] {
                result[env] = branch
            }
        }
        return result
    }

    // MARK: - Actions

    private var hasInitialized = false

    func initialize() async {
        // Runs once at launch (from the app delegate) - guard against the popover's
        // fallback `.task` also firing it if the window opens before launch finishes.
        guard !hasInitialized else { return }
        hasInitialized = true

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
            reportError(error)
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
            reportError(error)
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
        savePreferences()
    }

    func updateWatchedProject(_ project: WatchedProject) {
        if let index = preferences.watchedProjects.firstIndex(where: { $0.id == project.id }) {
            preferences.watchedProjects[index] = project
            savePreferences()
        }
    }
    
    func startPolling() {
        regroupBuilds()
        poller.startPolling(interval: TimeInterval(preferences.pollingIntervalSeconds))
        autoApprovalPoller.startPolling()
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

    /// Normalized key identifying a deployed branch. Case-insensitive so it
    /// matches regardless of how the branch/slug is cased in the builds API.
    nonisolated static func deployKey(projectSlug: String, branch: String) -> String {
        "\(projectSlug.lowercased())#\(branch.lowercased())"
    }

    /// Fire confetti + success sound unconditionally. Callers decide whether the
    /// branch/pref combination warrants a celebration and pass the kind so the
    /// banner reads correctly (production vs devnet).
    func celebrate(projectLabel: String, secondaryLabel: String? = nil, kind: CelebrationKind) {
        AudioPlayer.shared.play(CelebrationSound(rawValue: preferences.successSound) ?? .defaultSuccess)
        ConfettiPresenter.shared.present(projectLabel: projectLabel, secondaryLabel: secondaryLabel, kind: kind)
    }

    func celebrateProdSuccess(projectLabel: String) {
        guard preferences.celebrateProdSuccess else { return }
        celebrate(projectLabel: projectLabel, kind: .production)
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
            reportError(error)
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
            reportError(error)
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
        markBranchDeployed(projectSlug: project.slug, branch: branch)
        schedulePostTriggerRefresh()
        return pipeline
    }

    /// Arm the deployed-branch marker so the next successful pipeline on this
    /// branch celebrates. Re-arming would otherwise let an already-completed
    /// workflow from a prior deploy fire confetti on the next poll, so baseline
    /// every workflow currently known for the branch as handled: only the
    /// freshly triggered pipeline can celebrate.
    func markBranchDeployed(projectSlug: String, branch: String) {
        deployedBranchKeys.insert(Self.deployKey(projectSlug: projectSlug, branch: branch))
        let branchKey = branch.lowercased()
        let existingWorkflowIds = (buildsByProject[projectSlug] ?? [])
            .filter { $0.branch?.lowercased() == branchKey }
            .compactMap { $0.workflows?.workflowId }
        celebratedSuccessWorkflows.formUnion(existingWorkflowIds)
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

    /// Drops the row up front, because the next poll still reports the gate as `on_hold` for a
    /// few seconds.
    func approveJob(_ approval: PendingApproval) async {
        pendingApprovals.removeAll { $0.id == approval.id }
        do {
            try await CircleCIAPI.shared.approveJob(
                workflowId: approval.workflowId,
                approvalRequestId: approval.jobId
            )
        } catch {
            reportError(error)
        }
        poller.poll()
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
        KeychainService.shared.deleteToken()
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
        regroupBuilds()
        currentScreen = .onboarding
    }
    
    func changeToken() {
        // Preserve watchlist but clear token and go to onboarding
        stopPolling()
        KeychainService.shared.deleteToken()
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
        regroupBuilds()
        currentScreen = .onboarding
    }
    
    func savePreferences() {
        preferences.save()
        // Restart polling with new interval
        if poller.isPolling || vercelPoller.isPolling {
            startAllPolling()
        }
        // React immediately when the deploy-loader toggle changes.
        refreshDeploySpinner()
        regroupBuilds()
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
            reportError(error)
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
            backfillVercelScopeSlugs()
            isLoading = false
        } catch {
            reportError(error)
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
            reportError(error)
            isLoading = false
        }
    }
    
    func addVercelToWatchlist(_ project: VercelProject, teamId: String?, followMode: FollowMode = .all) {
        let watchedProject = WatchedVercelProject(
            from: project,
            teamId: teamId,
            teamSlug: vercelScopeSlug(forTeamId: teamId),
            followMode: followMode
        )
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
    
    func vercelScopeSlug(forTeamId teamId: String?) -> String? {
        guard let teamId else { return vercelUser?.username }
        return vercelTeams.first(where: { $0.id == teamId })?.slug
    }

    /// Projects watched before the scope slug was stored have no branch URL to open, so fetch the teams
    /// once on launch to fill it in.
    func resolveMissingVercelScopeSlugs() async {
        let missing = preferences.watchedVercelProjects.filter { $0.teamSlug == nil }
        guard !missing.isEmpty else { return }

        if vercelTeams.isEmpty, missing.contains(where: { $0.teamId != nil }) {
            vercelTeams = (try? await VercelAPI.shared.getTeams()) ?? []
        }
        backfillVercelScopeSlugs()
    }

    func disconnectVercel() {
        stopVercelPolling()
        KeychainService.shared.deleteVercelToken()
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

    private func backfillVercelScopeSlugs() {
        var didChange = false
        for index in preferences.watchedVercelProjects.indices
        where preferences.watchedVercelProjects[index].teamSlug == nil {
            guard let slug = vercelScopeSlug(forTeamId: preferences.watchedVercelProjects[index].teamId) else {
                continue
            }
            preferences.watchedVercelProjects[index].teamSlug = slug
            didChange = true
        }
        if didChange {
            preferences.save()
        }
    }

    private func restoreVercelSession() async {
        do {
            let response = try await VercelAPI.shared.validateToken()
            vercelUser = response.user
            await resolveMissingVercelScopeSlugs()
        } catch {
            // Keep the saved token for now; account details can be refreshed later.
            vercelUser = nil
        }
    }
    
    /// True for benign task / URL cancellations - e.g. the menu bar popover
    /// closing while a request is in flight. These are not real failures.
    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    /// Set the user-facing error, ignoring benign cancellations so a superseded
    /// or interrupted request never flashes a "cancelled" banner.
    func reportError(_ error: Error) {
        guard !isCancellation(error) else { return }
        self.error = error.localizedDescription
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
            // Only wipe credentials when the token is actually invalid. Onboarding
            // explains the reauth, so no banner here.
            if let circleError = error as? CircleCIError, case .unauthorized = circleError {
                KeychainService.shared.deleteToken()
                await CircleCIAPI.shared.clearToken()
                currentScreen = .onboarding
                isLoading = false
                return
            }

            // Transient error (offline, RBAC/403, rate limits, a cancelled request).
            // If projects are already set up, recover silently and let the poller keep
            // retrying every interval - no banner. Only first-run setup, which has no
            // data to fall back on, surfaces the error so the user knows to retry.
            if preferences.watchedProjects.isEmpty && preferences.watchedVercelProjects.isEmpty {
                reportError(error)
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
        case .failing: return "xmark.circle.fill"
        case .running: return "arrow.triangle.2.circlepath.circle.fill" // unused: the label draws an animated spinner
        case .pendingApproval: return "pause.circle.fill"
        case .unknown: return "circle.dashed"
        }
    }

    /// Hybrid menu-bar tint: color only for attention states, nil for calm
    /// states so they render monochrome/template and adapt to the menu bar.
    /// Colors match the glyphs used by build rows (RowStatus).
    var menuBarTint: Color? {
        switch self {
        case .failing: return AppChrome.danger
        case .pendingApproval: return AppChrome.warning
        case .passing, .running, .unknown: return nil
        }
    }
}
