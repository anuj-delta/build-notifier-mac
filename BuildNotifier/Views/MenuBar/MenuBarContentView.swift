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

struct MenuBarContentView: View {
    private let popoverWidth: CGFloat = 424
    private let buildsListMaxHeight: CGFloat = 1120
    private let buildsListMinHeight: CGFloat = 440

    @Bindable var appState: AppState
    @State private var isRefreshing = false
    @State private var selectedTab: MenuBarTab = .overview
    @State private var isSearchExpanded = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let snapshot = makeSnapshot()

        VStack(spacing: 0) {
            header(snapshot: snapshot)

            if let error = appState.error {
                ErrorBanner(
                    message: error,
                    onRetry: { appState.retryStartup() },
                    onChangeToken: { appState.changeToken() }
                )
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }

            if appState.watchedProjects.isEmpty && appState.watchedVercelProjects.isEmpty {
                emptyState
            } else {
                buildsList(snapshot: snapshot)
            }

            footer
        }
        .frame(width: popoverWidth)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            selectDefaultTabIfNeeded(tabs: snapshot.availableTabs)
            appState.refreshNow()
        }
    }

    private func header(snapshot: MenuBarSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AppBrandIcon(size: 30)

                Text("Delta Build Notifer")
                    .font(.headline)

                Spacer(minLength: 0)

                headerActions
            }

            if isSearchExpanded {
                searchField(activeTab: snapshot.activeTab)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if snapshot.availableTabs.count > 1 {
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
        .padding(.bottom, 10)
        .animation(.spring(response: 0.28, dampingFraction: 0.92), value: isSearchExpanded)
    }

    private var headerActions: some View {
        HStack(spacing: 6) {
            Button {
                toggleSearch()
            } label: {
                Image(systemName: isSearchExpanded ? "line.3.horizontal.decrease.circle.fill" : "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(Circle())
            .help(isSearchExpanded ? "Hide search" : "Search branches")

            Button {
                withAnimation(.linear(duration: 0.8).repeatCount(3, autoreverses: false)) {
                    isRefreshing = true
                }
                appState.refreshNow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                    isRefreshing = false
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(Circle())
            .help("Refresh now")

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(Circle())
            .help("Settings")
        }
    }

    private func searchField(activeTab: MenuBarTab) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(searchPlaceholder(for: activeTab), text: $searchText)
                .textFieldStyle(.plain)
                .font(.caption)
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.accentColor.opacity(isSearchFocused ? 0.35 : 0), lineWidth: 1)
        )
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
                    .font(.headline)

                Text("Add CircleCI or Vercel projects to keep recent build health in the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            LazyVStack(spacing: 10) {
                tabContent(snapshot: snapshot)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(minHeight: buildsListMinHeight, maxHeight: buildsListMaxHeight)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let lastPoll = latestPollTime {
                Label("Updated \(lastPoll.formatted(.relative(presentation: .named)))", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
                onApprove: { approval in
                    Task { await appState.approveJob(approval) }
                },
                onOpen: { approval in
                    openBuildUrl(approval.build.workflowUrl ?? approval.build.buildUrl)
                }
            )
        }

        if !snapshot.filteredGroupedBuilds.isEmpty {
            PopoverSectionHeader(
                title: "CircleCI",
                subtitle: snapshot.hasSearchQuery ? "Matching builds and approvals" : "Recent builds and approvals",
                markStyle: .circleCI
            )

            ForEach(snapshot.filteredGroupedBuilds, id: \.project.id) { item in
                ProjectSection(
                    project: item.project,
                    buildsByBranch: item.builds,
                    isFiltered: snapshot.hasSearchQuery,
                    onRetry: { build in
                        Task { await appState.retryBuild(build) }
                    },
                    onCancel: { build in
                        Task { await appState.cancelBuild(build) }
                    },
                    onOpen: { build in
                        openBuildUrl(build.workflowUrl ?? build.buildUrl)
                    }
                )
            }
        }

        if !snapshot.filteredVercelProjects.isEmpty {
            PopoverSectionHeader(
                title: "Vercel",
                subtitle: snapshot.hasSearchQuery ? "Matching deployments" : "Watched deployments",
                markStyle: .vercel
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
        ProviderSummaryCard(
            markStyle: .circleCI,
            title: "CircleCI",
            subtitle: "Builds, approvals, and quick actions for your tracked branches.",
            pillText: snapshot.circleCISummaryLabel
        )

        if !snapshot.filteredPendingApprovals.isEmpty {
            PendingApprovalsSection(
                approvals: snapshot.filteredPendingApprovals,
                onApprove: { approval in
                    Task { await appState.approveJob(approval) }
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
                    onRetry: { build in
                        Task { await appState.retryBuild(build) }
                    },
                    onCancel: { build in
                        Task { await appState.cancelBuild(build) }
                    },
                    onOpen: { build in
                        openBuildUrl(build.workflowUrl ?? build.buildUrl)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func vercelContent(snapshot: MenuBarSnapshot) -> some View {
        ProviderSummaryCard(
            markStyle: .vercel,
            title: "Vercel",
            subtitle: "Latest deployments from your watched preview and production projects.",
            pillText: snapshot.vercelSummaryLabel
        )

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
        withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
            isSearchExpanded.toggle()
        }

        if isSearchExpanded {
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        } else {
            isSearchFocused = false
            if trimmedSearchText.isEmpty {
                searchText = ""
            }
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
        openWindow(id: "settings")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func openBuildUrl(_ urlString: String?) {
        guard let urlString, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct MenuBarTabPicker: View {
    @Binding var selectedTab: MenuBarTab
    let tabs: [MenuBarTab]
    let countProvider: (MenuBarTab) -> Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        ProviderMark(style: tab.markStyle, color: selectedTab == tab ? .primary : .secondary, size: 12)

                        Text(tab.title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        Text("\(countProvider(tab))")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(selectedTab == tab ? Color.accentColor.opacity(0.16) : Color.clear)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(selectedTab == tab ? Color.accentColor.opacity(0.42) : Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(Capsule(style: .continuous))
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
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(pillText)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(999)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(14)
    }
}

struct ProviderEmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(14)
    }
}

struct PopoverSectionHeader: View {
    let title: String
    let subtitle: String
    let markStyle: ProviderMarkStyle

    var body: some View {
        HStack(spacing: 8) {
            ProviderMark(style: markStyle, color: .secondary, size: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
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
                    .foregroundStyle(.yellow)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .padding(12)
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(12)
    }
}

struct PendingApprovalsSection: View {
    let approvals: [PendingApproval]
    let onApprove: (PendingApproval) -> Void
    let onOpen: (PendingApproval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Pending Approvals", systemImage: "pause.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)

                Spacer()

                Text("\(approvals.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.16))
                    .cornerRadius(999)
            }

            ForEach(approvals) { approval in
                ApprovalRow(
                    approval: approval,
                    onApprove: { onApprove(approval) },
                    onOpen: { onOpen(approval) }
                )
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.06))
        .cornerRadius(14)
    }
}

struct ApprovalRow: View {
    let approval: PendingApproval
    let onApprove: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(approval.build.projectSlug)
                    .font(.caption)
                    .fontWeight(.semibold)

                Text("\(approval.jobName) • \(approval.build.branch ?? "unknown")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Approve") {
                onApprove()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)

            Button {
                onOpen()
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.plain)
            .help("Open in browser")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(10)
    }
}
