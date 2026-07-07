import SwiftUI

enum MenuBarTab: String, Hashable {
    case overview
    case circleCI
    case vercel

    var title: String {
        switch self {
        case .overview:
            return "All"
        case .circleCI:
            return "CircleCI"
        case .vercel:
            return "Vercel"
        }
    }

    var markStyle: ProviderMarkStyle {
        switch self {
        case .overview:
            return .overview
        case .circleCI:
            return .circleCI
        case .vercel:
            return .vercel
        }
    }
}

enum ProviderMarkStyle {
    case overview
    case circleCI
    case vercel
}

enum MenuPalette {
    static let backdrop = AppChrome.window
    static let card = AppChrome.surface
    static let cardBorder = AppChrome.border
    static let ink = AppChrome.text
    static let mutedInk = AppChrome.textMuted
    static let accent = AppChrome.accent
    static let accentSoft = AppChrome.accentSoft
    static let approval = AppChrome.warning
}

private struct FilteredVercelProject {
    let project: WatchedVercelProject
    let deployments: [VercelDeployment]
}

private struct MenuBarSnapshot {
    let availableTabs: [MenuBarTab]
    let activeTab: MenuBarTab
    let hasSearchQuery: Bool
    let filteredPendingApprovals: [PendingApproval]
    let filteredGroupedBuilds: [(project: WatchedProject, builds: [String: [Build]])]
    let filteredVercelProjects: [FilteredVercelProject]
    let circleCICount: Int
    let vercelCount: Int
    let circleCISummaryLabel: String
    let vercelSummaryLabel: String

    func count(for tab: MenuBarTab) -> Int {
        switch tab {
        case .overview:
            return circleCICount + vercelCount
        case .circleCI:
            return circleCICount
        case .vercel:
            return vercelCount
        }
    }
}

private enum PendingMenuAction {
    case approve(PendingApproval)
    case retry(Build)
    case cancel(Build)

    var title: String {
        switch self {
        case .approve(let approval):
            return "Approve \(approval.jobName)?"
        case .retry(let build):
            return "Retry Build #\(build.buildNum)?"
        case .cancel(let build):
            return "Cancel Build #\(build.buildNum)?"
        }
    }

    var message: String {
        switch self {
        case .approve(let approval):
            return "This will approve the workflow for \(approval.build.branch ?? "this branch")."
        case .retry(let build):
            return "This will create a new build for \(build.branch ?? "this branch")."
        case .cancel:
            return "This will stop the currently running build."
        }
    }

    var confirmTitle: String {
        switch self {
        case .approve:
            return "Approve"
        case .retry:
            return "Retry"
        case .cancel:
            return "Cancel Build"
        }
    }

    var confirmRole: ButtonRole? {
        switch self {
        case .cancel:
            return .destructive
        case .approve, .retry:
            return nil
        }
    }

    var icon: String {
        switch self {
        case .approve:
            return "checkmark.seal.fill"
        case .retry:
            return "arrow.clockwise"
        case .cancel:
            return "xmark.octagon.fill"
        }
    }

    var accent: Color {
        confirmRole == .destructive ? AppChrome.danger : AppChrome.accent
    }

    var cancelTitle: String {
        switch self {
        case .approve:
            return "Not Now"
        case .retry:
            return "Keep Current Build"
        case .cancel:
            return "Keep Running"
        }
    }
}

struct MenuBarContentView: View {
    private let popoverWidth: CGFloat = 424
    private let buildsListMaxHeight: CGFloat = 1120
    private let buildsListMinHeight: CGFloat = 440

    @Bindable var appState: AppState
    @State private var isRefreshing = false
    @State private var selectedTab: MenuBarTab = .overview
    @State private var isSearchExpanded = false
    @State private var searchText = ""
    @State private var pendingAction: PendingMenuAction?
    @State private var deployTarget: WatchedProject?
    @FocusState private var isSearchFocused: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let snapshot = makeSnapshot()

        ZStack {
            VStack(spacing: 0) {
                header(snapshot: snapshot)

                if let error = appState.error {
                    ErrorBanner(
                        message: error,
                        onRetry: { appState.retryStartup() },
                        onChangeToken: { appState.changeToken() }
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                }

                if appState.watchedProjects.isEmpty && appState.watchedVercelProjects.isEmpty {
                    emptyState
                } else {
                    buildsList(snapshot: snapshot)
                }

                footer
            }
            .background(GlassBackground(cornerRadius: 13))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(AppChrome.glassStroke, lineWidth: 1)
            }
            .background(MenuWindowConfigurator())

            if let pendingAction {
                PendingActionOverlay(
                    action: pendingAction,
                    onConfirm: {
                        perform(pendingAction)
                    },
                    onCancel: {
                        self.pendingAction = nil
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(1)
            }

            if let deployTarget {
                DeployBranchOverlay(
                    project: deployTarget,
                    appState: appState,
                    onDismiss: { self.deployTarget = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(2)
            }
        }
        .frame(width: popoverWidth)
        .background {
            Button(action: openSearch) { EmptyView() }
                .keyboardShortcut("s", modifiers: [])
                .disabled(isSearchExpanded)
                .opacity(0)
                .accessibilityHidden(true)

            Button(action: closeSearch) { EmptyView() }
                .keyboardShortcut(.cancelAction)
                .disabled(!isSearchExpanded)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .animation(.easeInOut(duration: 0.16), value: pendingAction != nil)
        .animation(.easeInOut(duration: 0.16), value: deployTarget != nil)
        .onAppear {
            selectDefaultTabIfNeeded(tabs: snapshot.availableTabs)
            appState.refreshNow()
        }
    }

    private func header(snapshot: MenuBarSnapshot) -> some View {
        let showsTabs = snapshot.availableTabs.count > 1

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AppBrandIcon(size: 26)

                Text("Build Notifier")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MenuPalette.ink)

                Spacer(minLength: 0)

                headerActions
            }

            if isSearchExpanded {
                searchField(activeTab: snapshot.activeTab)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showsTabs {
                MenuBarTabPicker(
                    selectedTab: Binding(
                        get: { snapshot.activeTab },
                        set: { selectedTab = $0 }
                    ),
                    tabs: snapshot.availableTabs,
                    countProvider: snapshot.count(for:)
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, showsTabs ? 0 : 10)
        .overlay(alignment: .bottom) {
            if !showsTabs {
                Rectangle()
                    .fill(AppChrome.separator)
                    .frame(height: 1)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.92), value: isSearchExpanded)
    }

    private var headerActions: some View {
        HStack(spacing: 2) {
            HeaderIconButton(
                systemName: isSearchExpanded ? "line.3.horizontal.decrease.circle.fill" : "magnifyingglass",
                help: isSearchExpanded ? "Hide search" : "Search branches",
                accessibilityLabel: isSearchExpanded ? "Hide search" : "Search branches",
                isActive: isSearchExpanded
            ) {
                toggleSearch()
            }

            HeaderIconButton(
                systemName: "arrow.clockwise",
                help: "Refresh now",
                accessibilityLabel: "Refresh now",
                rotation: isRefreshing ? 360 : 0
            ) {
                withAnimation(.linear(duration: 0.8).repeatCount(3, autoreverses: false)) {
                    isRefreshing = true
                }
                appState.refreshNow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                    isRefreshing = false
                }
            }

            HeaderIconButton(
                systemName: "gearshape.fill",
                help: "Settings",
                accessibilityLabel: "Open settings"
            ) {
                openSettings()
            }
        }
    }

    private func searchField(activeTab: MenuBarTab) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSearchFocused ? AppChrome.accent : MenuPalette.mutedInk)

            TextField(searchPlaceholder(for: activeTab), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .focused($isSearchFocused)

            if searchText.isEmpty {
                Text("esc")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MenuPalette.mutedInk)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(AppChrome.hover)
                    )
            } else {
                Button {
                    clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(MenuPalette.mutedInk)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AppChrome.rowHover)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSearchFocused ? AppChrome.accent.opacity(0.7) : AppChrome.glassStroke, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.14), value: isSearchFocused)
        .onChange(of: isSearchFocused) { _, focused in
            if !focused && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                    isSearchExpanded = false
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 8)

            AppBrandIcon(size: 62)

            VStack(spacing: 6) {
                Text("Nothing is being watched yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MenuPalette.ink)

                Text("Add CircleCI or Vercel projects to keep recent build health in the menu bar.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(MenuPalette.mutedInk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            HStack(spacing: 10) {
                if appState.hasCircleCIToken {
                    Button("Add CircleCI Projects") {
                        appState.currentScreen = .projectSelection
                        appState.stopPolling()
                        Task {
                            await appState.loadProjects()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button("Open Settings") {
                    openSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func buildsList(snapshot: MenuBarSnapshot) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                tabContent(snapshot: snapshot)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(minHeight: buildsListMinHeight, maxHeight: buildsListMaxHeight)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let lastPoll = latestPollTime {
                Label("Updated \(lastPoll.formatted(.relative(presentation: .named)))", systemImage: "clock")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(MenuPalette.mutedInk)
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(MenuPalette.mutedInk)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppChrome.separator)
                .frame(height: 1)
        }
    }

    private var latestPollTime: Date? {
        let times = [appState.poller.lastPollTime, appState.vercelPoller.lastPollTime].compactMap { $0 }
        return times.max()
    }

    private func makeSnapshot() -> MenuBarSnapshot {
        let groupedBuilds = appState.groupedBuilds
        let normalizedSearchText = trimmedSearchText
        let hasSearchQuery = !normalizedSearchText.isEmpty

        let hasCircleCIContent = !groupedBuilds.isEmpty || !appState.pendingApprovals.isEmpty || !appState.watchedProjects.isEmpty
        let hasVercelContent = !appState.watchedVercelProjects.isEmpty

        var tabs: [MenuBarTab] = []
        if hasCircleCIContent && hasVercelContent {
            tabs.append(.overview)
        }
        if hasCircleCIContent {
            tabs.append(.circleCI)
        }
        if hasVercelContent {
            tabs.append(.vercel)
        }

        let availableTabs = tabs.isEmpty ? [.overview] : tabs
        let activeTab = availableTabs.contains(selectedTab) ? selectedTab : (availableTabs.first ?? .overview)

        let filteredPendingApprovals: [PendingApproval]
        if hasSearchQuery {
            filteredPendingApprovals = appState.pendingApprovals.filter { approval in
                branchMatchesSearch(approval.build.branch, searchText: normalizedSearchText)
            }
        } else {
            filteredPendingApprovals = appState.pendingApprovals
        }

        let filteredGroupedBuilds: [(project: WatchedProject, builds: [String: [Build]])]
        if hasSearchQuery {
            filteredGroupedBuilds = groupedBuilds.compactMap { item in
                let filtered = item.builds.filter { branch, builds in
                    branchMatchesSearch(branch, searchText: normalizedSearchText) ||
                    builds.contains(where: { branchMatchesSearch($0.branch, searchText: normalizedSearchText) })
                }

                guard !filtered.isEmpty else { return nil }
                return (project: item.project, builds: filtered)
            }
        } else {
            filteredGroupedBuilds = groupedBuilds
        }

        let filteredVercelProjects = appState.watchedVercelProjects.compactMap { project -> FilteredVercelProject? in
            let deployments = appState.deploymentsByProject[project.id] ?? []
            let filteredDeployments = hasSearchQuery
                ? deployments.filter { branchMatchesSearch($0.meta?.branch, searchText: normalizedSearchText) }
                : deployments

            guard !hasSearchQuery || !filteredDeployments.isEmpty else { return nil }
            return FilteredVercelProject(project: project, deployments: filteredDeployments)
        }

        let circleCISummaryLabel: String
        if !filteredPendingApprovals.isEmpty {
            circleCISummaryLabel = "\(appState.watchedProjects.count) projects • \(filteredPendingApprovals.count) approvals"
        } else {
            circleCISummaryLabel = "\(appState.watchedProjects.count) projects"
        }

        let deploymentCount = filteredVercelProjects.reduce(into: 0) { partialResult, project in
            partialResult += project.deployments.count
        }
        let vercelSummaryLabel = deploymentCount > 0
            ? "\(appState.watchedVercelProjects.count) projects • \(deploymentCount) deployments"
            : "\(appState.watchedVercelProjects.count) projects"

        return MenuBarSnapshot(
            availableTabs: availableTabs,
            activeTab: activeTab,
            hasSearchQuery: hasSearchQuery,
            filteredPendingApprovals: filteredPendingApprovals,
            filteredGroupedBuilds: filteredGroupedBuilds,
            filteredVercelProjects: filteredVercelProjects,
            circleCICount: appState.watchedProjects.count,
            vercelCount: appState.watchedVercelProjects.count,
            circleCISummaryLabel: circleCISummaryLabel,
            vercelSummaryLabel: vercelSummaryLabel
        )
    }

    @ViewBuilder
    private func tabContent(snapshot: MenuBarSnapshot) -> some View {
        switch snapshot.activeTab {
        case .overview:
            overviewContent(snapshot: snapshot)
        case .circleCI:
            circleCIContent(snapshot: snapshot)
        case .vercel:
            vercelContent(snapshot: snapshot)
        }
    }

    @ViewBuilder
    private func overviewContent(snapshot: MenuBarSnapshot) -> some View {
        if !snapshot.filteredPendingApprovals.isEmpty {
            PendingApprovalsSection(
                approvals: snapshot.filteredPendingApprovals,
                armedAutoApprovalWorkflowIds: appState.armedAutoApprovalWorkflowIds,
                onApprove: { approval in
                    pendingAction = .approve(approval)
                },
                onArmAutoApprove: { approval in
                    appState.armAutoApprove(for: approval.build)
                },
                onCancelAutoApprove: { approval in
                    appState.cancelAutoApprove(forWorkflowId: approval.workflowId)
                },
                onOpen: { approval in
                    openBuildUrl(approval.build.workflowUrl ?? approval.build.buildUrl)
                }
            )
        }

        if !snapshot.filteredGroupedBuilds.isEmpty {
            PopoverSectionHeader(
                title: "CircleCI",
                subtitle: snapshot.hasSearchQuery ? "Matching builds and approvals" : "Recent builds and approvals"
            )

            ForEach(snapshot.filteredGroupedBuilds, id: \.project.id) { item in
                ProjectSection(
                    project: item.project,
                    buildsByBranch: item.builds,
                    isFiltered: snapshot.hasSearchQuery,
                    approvalCapableWorkflowIds: appState.approvalCapableWorkflowIds,
                    armedAutoApprovalWorkflowIds: appState.armedAutoApprovalWorkflowIds,
                    onRetry: { build in
                        pendingAction = .retry(build)
                    },
                    onCancel: { build in
                        pendingAction = .cancel(build)
                    },
                    onArmAutoApprove: { build in
                        appState.armAutoApprove(for: build)
                    },
                    onCancelAutoApprove: { workflowId in
                        appState.cancelAutoApprove(forWorkflowId: workflowId)
                    },
                    onOpen: { build in
                        openBuildUrl(build.workflowUrl ?? build.buildUrl)
                    },
                    onOpenPR: { build in
                        openBuildUrl(build.pullRequestUrl)
                    },
                    onOpenRepo: { repoUrl in
                        openBuildUrl(repoUrl)
                    },
                    onDeploy: { project in
                        deployTarget = project
                    }
                )
            }
        }

        if !snapshot.filteredVercelProjects.isEmpty {
            PopoverSectionHeader(
                title: "Vercel",
                subtitle: snapshot.hasSearchQuery ? "Matching deployments" : "Watched deployments"
            )

            ForEach(snapshot.filteredVercelProjects, id: \.project.id) { item in
                VercelProjectSection(
                    project: item.project,
                    deployments: item.deployments,
                    isFiltered: snapshot.hasSearchQuery
                )
            }
        }

        if snapshot.hasSearchQuery &&
            snapshot.filteredPendingApprovals.isEmpty &&
            snapshot.filteredGroupedBuilds.isEmpty &&
            snapshot.filteredVercelProjects.isEmpty {
            ProviderEmptyStateCard(
                title: "No matching results",
                message: "Try a different branch name or clear the filter to see all builds and deployments."
            )
        }
    }

    @ViewBuilder
    private func circleCIContent(snapshot: MenuBarSnapshot) -> some View {
        if !snapshot.filteredPendingApprovals.isEmpty {
            PendingApprovalsSection(
                approvals: snapshot.filteredPendingApprovals,
                armedAutoApprovalWorkflowIds: appState.armedAutoApprovalWorkflowIds,
                onApprove: { approval in
                    pendingAction = .approve(approval)
                },
                onArmAutoApprove: { approval in
                    appState.armAutoApprove(for: approval.build)
                },
                onCancelAutoApprove: { approval in
                    appState.cancelAutoApprove(forWorkflowId: approval.workflowId)
                },
                onOpen: { approval in
                    openBuildUrl(approval.build.workflowUrl ?? approval.build.buildUrl)
                }
            )
        }

        if snapshot.filteredGroupedBuilds.isEmpty {
            ProviderEmptyStateCard(
                title: snapshot.hasSearchQuery ? "No matching CircleCI branches" : "No CircleCI builds yet",
                message: snapshot.hasSearchQuery
                    ? "Try a different branch name or clear the filter to see all tracked branches."
                    : "Tracked projects will appear here after the next successful poll."
            )
        } else {
            ForEach(snapshot.filteredGroupedBuilds, id: \.project.id) { item in
                ProjectSection(
                    project: item.project,
                    buildsByBranch: item.builds,
                    isFiltered: snapshot.hasSearchQuery,
                    approvalCapableWorkflowIds: appState.approvalCapableWorkflowIds,
                    armedAutoApprovalWorkflowIds: appState.armedAutoApprovalWorkflowIds,
                    onRetry: { build in
                        pendingAction = .retry(build)
                    },
                    onCancel: { build in
                        pendingAction = .cancel(build)
                    },
                    onArmAutoApprove: { build in
                        appState.armAutoApprove(for: build)
                    },
                    onCancelAutoApprove: { workflowId in
                        appState.cancelAutoApprove(forWorkflowId: workflowId)
                    },
                    onOpen: { build in
                        openBuildUrl(build.workflowUrl ?? build.buildUrl)
                    },
                    onOpenPR: { build in
                        openBuildUrl(build.pullRequestUrl)
                    },
                    onOpenRepo: { repoUrl in
                        openBuildUrl(repoUrl)
                    },
                    onDeploy: { project in
                        deployTarget = project
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func vercelContent(snapshot: MenuBarSnapshot) -> some View {
        if appState.watchedVercelProjects.isEmpty {
            ProviderEmptyStateCard(
                title: "No Vercel projects selected",
                message: "Add Vercel projects in Settings to monitor deployment status here."
            )
        } else if snapshot.filteredVercelProjects.isEmpty {
            ProviderEmptyStateCard(
                title: "No matching Vercel branches",
                message: "Try a different branch name or clear the filter to see all recent deployments."
            )
        } else {
            ForEach(snapshot.filteredVercelProjects, id: \.project.id) { item in
                VercelProjectSection(
                    project: item.project,
                    deployments: item.deployments,
                    isFiltered: snapshot.hasSearchQuery
                )
            }
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func selectDefaultTabIfNeeded(tabs: [MenuBarTab]) {
        if !tabs.contains(selectedTab) {
            selectedTab = tabs.first ?? .overview
        }
    }

    private func toggleSearch() {
        if isSearchExpanded {
            closeSearch()
        } else {
            openSearch()
        }
    }

    private func openSearch() {
        if !isSearchExpanded {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                isSearchExpanded = true
            }
        }
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    private func closeSearch() {
        isSearchFocused = false
        searchText = ""
        withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
            isSearchExpanded = false
        }
    }

    private func clearSearch() {
        searchText = ""
        if !isSearchFocused {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                isSearchExpanded = false
            }
        }
    }

    private func searchPlaceholder(for activeTab: MenuBarTab) -> String {
        switch activeTab {
        case .overview:
            return "Filter all branches"
        case .circleCI:
            return "Filter CircleCI branches"
        case .vercel:
            return "Filter Vercel branches"
        }
    }

    private func branchMatchesSearch(_ branch: String?, searchText: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        return (branch ?? "").localizedCaseInsensitiveContains(searchText)
    }

    private func openSettings() {
        AppWindowManager.dismissActiveMenuBarWindow {
            openWindow(id: "settings")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func openBuildUrl(_ urlString: String?) {
        guard let urlString, let url = URL(string: urlString) else { return }
        AppWindowManager.dismissActiveMenuBarWindow {
            NSWorkspace.shared.open(url)
        }
    }

    private func perform(_ action: PendingMenuAction) {
        pendingAction = nil

        switch action {
        case .approve(let approval):
            Task { await appState.approveJob(approval) }
        case .retry(let build):
            Task { await appState.retryBuild(build) }
        case .cancel(let build):
            Task { await appState.cancelBuild(build) }
        }
    }

    private func cancelTitle(for action: PendingMenuAction) -> String {
        switch action {
        case .approve:
            return "Not Now"
        case .retry:
            return "Keep Current Build"
        case .cancel:
            return "Keep Running"
        }
    }
}

private struct PendingActionOverlay: View {
    let action: PendingMenuAction
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            ModalScrim(onDismiss: onCancel)

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: action.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(action.accent)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(action.accent.opacity(0.14))
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(action.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppChrome.text)

                        Text(action.message)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(AppChrome.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    Button(action.cancelTitle) { onCancel() }
                        .buttonStyle(ModalActionButtonStyle(kind: .secondary))

                    Button(action.confirmTitle) { onConfirm() }
                        .buttonStyle(ModalActionButtonStyle(
                            kind: action.confirmRole == .destructive ? .destructive : .primary
                        ))
                }
            }
            .padding(20)
            .modalSurface(width: 320)
        }
    }
}

private struct HeaderIconButton: View {
    let systemName: String
    let help: String
    let accessibilityLabel: String
    var rotation: Double = 0
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive || isHovered ? AppChrome.text : AppChrome.textMuted)
                .rotationEffect(.degrees(rotation))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovered ? AppChrome.hover : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointingHandCursor()
        .help(help)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct MenuBarTabPicker: View {
    @Binding var selectedTab: MenuBarTab
    let tabs: [MenuBarTab]
    let countProvider: (MenuBarTab) -> Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { tab in
                let isSelected = selectedTab == tab

                Button {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.title)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? AppChrome.text : AppChrome.textMuted)
                            .lineLimit(1)

                        Text("\(countProvider(tab))")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? AppChrome.accent : AppChrome.textMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(isSelected ? AppChrome.accentSoft : AppChrome.surfaceMuted)
                            )
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 9)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(isSelected ? AppChrome.accent : Color.clear)
                            .frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }

            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppChrome.separator)
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProviderSummaryCard: View {
    let markStyle: ProviderMarkStyle
    let title: String
    let subtitle: String
    let pillText: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProviderMark(style: markStyle, color: Color.accentColor, size: 14)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MenuPalette.ink)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(MenuPalette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(pillText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MenuPalette.mutedInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(AppChrome.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: AppChrome.radiusSmall, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppChrome.radiusSmall, style: .continuous)
                        .stroke(AppChrome.border, lineWidth: 1)
                }
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppChrome.separator)
                .frame(height: 1)
        }
    }
}

struct ProviderEmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MenuPalette.ink)

            Text(message)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(MenuPalette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppChrome.separator)
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppChrome.separator)
                .frame(height: 1)
        }
    }
}

struct PopoverSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MenuPalette.ink)
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(MenuPalette.mutedInk)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct ProviderMark: View {
    let style: ProviderMarkStyle
    let color: Color
    let size: CGFloat

    var body: some View {
        Group {
            switch style {
            case .overview:
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(color)
            case .circleCI:
                Text("C")
                    .font(.system(size: size, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            case .vercel:
                Image(systemName: "triangle.fill")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size + 2, height: size + 2)
    }
}

struct ErrorBanner: View {
    let message: String
    let onRetry: () -> Void
    let onChangeToken: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(MenuPalette.approval)

                Text(message)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(MenuPalette.mutedInk)
                    .lineLimit(3)

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button("Retry") {
                    onRetry()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Change Token") {
                    onChangeToken()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(MenuPalette.approval.opacity(0.08))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(MenuPalette.approval)
                .frame(width: 2)
        }
    }
}

struct PendingApprovalsSection: View {
    let approvals: [PendingApproval]
    let armedAutoApprovalWorkflowIds: Set<String>
    let onApprove: (PendingApproval) -> Void
    let onArmAutoApprove: (PendingApproval) -> Void
    let onCancelAutoApprove: (PendingApproval) -> Void
    let onOpen: (PendingApproval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Pending Approvals")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MenuPalette.ink)

                Spacer()

                Text("\(approvals.count)")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(MenuPalette.approval)
                    .background(MenuPalette.approval.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: AppChrome.radiusSmall, style: .continuous))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ForEach(Array(approvals.enumerated()), id: \.element.id) { index, approval in
                ApprovalRow(
                    approval: approval,
                    isAutoApproveArmed: armedAutoApprovalWorkflowIds.contains(approval.workflowId),
                    onApprove: { onApprove(approval) },
                    onAutoApprove: { onArmAutoApprove(approval) },
                    onCancelAutoApprove: { onCancelAutoApprove(approval) },
                    onOpen: { onOpen(approval) }
                )

                if index < approvals.count - 1 {
                    Divider()
                }
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(MenuPalette.approval.opacity(0.24))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MenuPalette.approval.opacity(0.24))
                .frame(height: 1)
        }
    }
}

struct ApprovalRow: View {
    let approval: PendingApproval
    let isAutoApproveArmed: Bool
    let onApprove: () -> Void
    let onAutoApprove: () -> Void
    let onCancelAutoApprove: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(MenuPalette.approval)
                .frame(width: 14, height: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    RepositoryPathLabel(
                        organization: approval.build.projectOrganizationName,
                        repository: approval.build.projectRepositoryName,
                        repositoryFont: .system(size: 13, weight: .semibold),
                        organizationFont: .system(size: 13, weight: .medium),
                        repositoryColor: MenuPalette.ink,
                        organizationColor: MenuPalette.mutedInk,
                        truncationMode: .middle
                    )

                    if isAutoApproveArmed {
                        Text("Armed")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppChrome.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppChrome.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }

                Text("\(approval.build.branch ?? "unknown") • \(approval.jobName)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(MenuPalette.mutedInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Approve") {
                onApprove()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)

            Menu {
                Button(isAutoApproveArmed ? "Cancel Auto-Approve" : "Auto-Approve") {
                    if isAutoApproveArmed {
                        onCancelAutoApprove()
                    } else {
                        onAutoApprove()
                    }
                }

                Button("Open in Browser") {
                    onOpen()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isAutoApproveArmed ? AppChrome.accent : MenuPalette.mutedInk)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("More actions")
            .accessibilityLabel("More approval actions")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
