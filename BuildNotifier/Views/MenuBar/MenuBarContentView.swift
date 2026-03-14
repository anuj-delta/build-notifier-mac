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

    var systemImage: String {
        switch self {
        case .overview:
            return "square.grid.2x2.fill"
        case .circleCI:
            return "arrow.triangle.branch"
        case .vercel:
            return "triangle.fill"
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
        VStack(spacing: 0) {
            header

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
                buildsList
            }

            footer
        }
        .frame(width: popoverWidth)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            selectDefaultTabIfNeeded()
            appState.refreshNow()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AppBrandIcon(size: 30)

                Text("Delta Build Notifer")
                    .font(.headline)

                Spacer(minLength: 0)

                headerActions
            }

            if isSearchExpanded {
                searchField
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if availableTabs.count > 1 {
                MenuBarTabPicker(
                    selectedTab: Binding(
                        get: { activeTab },
                        set: { selectedTab = $0 }
                    ),
                    tabs: availableTabs,
                    countProvider: count(for:)
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

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(searchPlaceholder, text: $searchText)
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

    private var buildsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                tabContent
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

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSearchQuery: Bool {
        !normalizedSearchText.isEmpty
    }

    private var filteredPendingApprovals: [PendingApproval] {
        guard hasSearchQuery else { return appState.pendingApprovals }
        return appState.pendingApprovals.filter { approval in
            branchMatchesSearch(approval.build.branch)
        }
    }

    private var filteredGroupedBuilds: [(project: WatchedProject, builds: [String: [Build]])] {
        guard hasSearchQuery else { return appState.groupedBuilds }

        return appState.groupedBuilds.compactMap { item in
            let filtered = item.builds.filter { branch, builds in
                branchMatchesSearch(branch) || builds.contains(where: { branchMatchesSearch($0.branch) })
            }

            guard !filtered.isEmpty else { return nil }
            return (project: item.project, builds: filtered)
        }
    }

    private var filteredVercelProjects: [(project: WatchedVercelProject, deployments: [VercelDeployment])] {
        appState.watchedVercelProjects.compactMap { project in
            let deployments = appState.deploymentsByProject[project.id] ?? []
            let filtered = hasSearchQuery ? deployments.filter { branchMatchesSearch($0.meta?.branch) } : deployments

            guard !hasSearchQuery || !filtered.isEmpty else { return nil }
            return (project: project, deployments: filtered)
        }
    }

    private var availableTabs: [MenuBarTab] {
        let hasCircleCIContent = !appState.groupedBuilds.isEmpty || !appState.pendingApprovals.isEmpty || !appState.watchedProjects.isEmpty
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

        return tabs.isEmpty ? [.overview] : tabs
    }

    private var activeTab: MenuBarTab {
        if availableTabs.contains(selectedTab) {
            return selectedTab
        }
        return availableTabs.first ?? .overview
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .overview:
            overviewContent
        case .circleCI:
            circleCIContent
        case .vercel:
            vercelContent
        }
    }

    @ViewBuilder
    private var overviewContent: some View {
        if !filteredPendingApprovals.isEmpty {
            PendingApprovalsSection(
                approvals: filteredPendingApprovals,
                onApprove: { approval in
                    Task { await appState.approveJob(approval) }
                },
                onOpen: { approval in
                    openBuildUrl(approval.build.workflowUrl ?? approval.build.buildUrl)
                }
            )
        }

        if !filteredGroupedBuilds.isEmpty {
            PopoverSectionHeader(
                title: "CircleCI",
                subtitle: hasSearchQuery ? "Matching builds and approvals" : "Recent builds and approvals",
                systemImage: "arrow.triangle.branch"
            )

            ForEach(filteredGroupedBuilds, id: \.project.id) { item in
                ProjectSection(
                    project: item.project,
                    buildsByBranch: item.builds,
                    isFiltered: hasSearchQuery,
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

        if !filteredVercelProjects.isEmpty {
            PopoverSectionHeader(
                title: "Vercel",
                subtitle: hasSearchQuery ? "Matching deployments" : "Watched deployments",
                systemImage: "triangle.fill"
            )

            ForEach(filteredVercelProjects, id: \.project.id) { item in
                VercelProjectSection(
                    project: item.project,
                    deployments: item.deployments,
                    isFiltered: hasSearchQuery
                )
            }
        }

        if hasSearchQuery && filteredPendingApprovals.isEmpty && filteredGroupedBuilds.isEmpty && filteredVercelProjects.isEmpty {
            ProviderEmptyStateCard(
                title: "No matching results",
                message: "Try a different branch name or clear the filter to see all builds and deployments."
            )
        }
    }

    @ViewBuilder
    private var circleCIContent: some View {
        ProviderSummaryCard(
            systemImage: "arrow.triangle.branch",
            title: "CircleCI",
            subtitle: "Builds, approvals, and quick actions for your tracked branches.",
            pillText: circleCISummaryLabel
        )

        if !filteredPendingApprovals.isEmpty {
            PendingApprovalsSection(
                approvals: filteredPendingApprovals,
                onApprove: { approval in
                    Task { await appState.approveJob(approval) }
                },
                onOpen: { approval in
                    openBuildUrl(approval.build.workflowUrl ?? approval.build.buildUrl)
                }
            )
        }

        if filteredGroupedBuilds.isEmpty {
            ProviderEmptyStateCard(
                title: hasSearchQuery ? "No matching CircleCI branches" : "No CircleCI builds yet",
                message: hasSearchQuery
                    ? "Try a different branch name or clear the filter to see all tracked branches."
                    : "Tracked projects will appear here after the next successful poll."
            )
        } else {
            ForEach(filteredGroupedBuilds, id: \.project.id) { item in
                ProjectSection(
                    project: item.project,
                    buildsByBranch: item.builds,
                    isFiltered: hasSearchQuery,
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
    private var vercelContent: some View {
        ProviderSummaryCard(
            systemImage: "triangle.fill",
            title: "Vercel",
            subtitle: "Latest deployments from your watched preview and production projects.",
            pillText: vercelSummaryLabel
        )

        if appState.watchedVercelProjects.isEmpty {
            ProviderEmptyStateCard(
                title: "No Vercel projects selected",
                message: "Add Vercel projects in Settings to monitor deployment status here."
            )
        } else if filteredVercelProjects.isEmpty {
            ProviderEmptyStateCard(
                title: "No matching Vercel branches",
                message: "Try a different branch name or clear the filter to see all recent deployments."
            )
        } else {
            ForEach(filteredVercelProjects, id: \.project.id) { item in
                VercelProjectSection(
                    project: item.project,
                    deployments: item.deployments,
                    isFiltered: hasSearchQuery
                )
            }
        }
    }

    private var circleCISummaryLabel: String {
        let approvals = appState.pendingApprovals.count
        if approvals > 0 {
            return "\(appState.watchedProjects.count) projects • \(approvals) approvals"
        }
        return "\(appState.watchedProjects.count) projects"
    }

    private var vercelSummaryLabel: String {
        let deploymentCount = appState.watchedVercelProjects.reduce(into: 0) { partialResult, project in
            partialResult += appState.deploymentsByProject[project.id]?.count ?? 0
        }
        if deploymentCount > 0 {
            return "\(appState.watchedVercelProjects.count) projects • \(deploymentCount) deployments"
        }
        return "\(appState.watchedVercelProjects.count) projects"
    }

    private func count(for tab: MenuBarTab) -> Int {
        switch tab {
        case .overview:
            return appState.watchedProjects.count + appState.watchedVercelProjects.count
        case .circleCI:
            return appState.watchedProjects.count
        case .vercel:
            return appState.watchedVercelProjects.count
        }
    }

    private func selectDefaultTabIfNeeded() {
        if !availableTabs.contains(selectedTab) {
            selectedTab = availableTabs.first ?? .overview
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
            if normalizedSearchText.isEmpty {
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

    private var searchPlaceholder: String {
        switch activeTab {
        case .overview:
            return "Filter all branches"
        case .circleCI:
            return "Filter CircleCI branches"
        case .vercel:
            return "Filter Vercel branches"
        }
    }

    private func branchMatchesSearch(_ branch: String?) -> Bool {
        guard hasSearchQuery else { return true }
        return (branch ?? "").localizedCaseInsensitiveContains(normalizedSearchText)
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
                    selectedTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                            .font(.caption2)

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
    let systemImage: String
    let title: String
    let subtitle: String
    let pillText: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
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
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
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
