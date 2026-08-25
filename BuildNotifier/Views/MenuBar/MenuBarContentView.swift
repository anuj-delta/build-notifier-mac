import SwiftUI

enum MenuPalette {
    static let ink = AppChrome.text
    static let mutedInk = AppChrome.textMuted
    static let approval = AppChrome.warning
}

/// Repository cards with a hairline between them, so one repo's last row never reads as the
/// next repo's first.
private struct SeparatedSections<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let section: (Item) -> Content

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index > 0 {
                Rectangle()
                    .fill(AppChrome.separator)
                    .frame(height: 1)
            }

            section(item)
        }
    }
}

private struct MenuBarSnapshot {
    let hasSearchQuery: Bool
    let filteredPendingApprovals: [PendingApproval]
    let filteredCards: [RepoCard]
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

private struct DeployTarget: Equatable {
    let project: WatchedProject
    var branch: String = ""
}

struct MenuBarContentView: View {
    private let popoverWidth: CGFloat = 424

    @Environment(MenuMetrics.self) private var metrics
    @Bindable var appState: AppState
    @State private var isRefreshing = false
    @State private var isSearchExpanded = false
    @State private var searchText = ""
    @State private var pendingAction: PendingMenuAction?
    @State private var deployTarget: DeployTarget?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let snapshot = makeSnapshot()

        ZStack {
            VStack(spacing: 0) {
                header

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
                    cardList(snapshot: snapshot)
                }

                footer

                MenuResizeHandle()
            }

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
                    project: deployTarget.project,
                    branch: deployTarget.branch,
                    appState: appState,
                    onDismiss: { self.deployTarget = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(2)
            }
        }
        .frame(width: popoverWidth, height: metrics.height)
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
        .animation(Motion.state, value: pendingAction != nil)
        .animation(Motion.state, value: deployTarget != nil)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AppBrandIcon(size: 26)

                Text("Build Notifier")
                    .font(Typography.title)
                    .typographyTracking(forSize: 15)
                    .foregroundStyle(MenuPalette.ink)

                if let update = appState.availableUpdate {
                    UpdatePill(version: update.version) {
                        openBuildUrl(update.releaseURL.absoluteString)
                    }
                }

                Spacer(minLength: 0)

                headerActions
            }

            if isSearchExpanded {
                searchField
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppChrome.separator)
                .frame(height: 1)
        }
        .animation(Motion.spring, value: isSearchExpanded)
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
                isLoading: isRefreshing
            ) {
                isRefreshing = true
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

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSearchFocused ? AppChrome.accent : MenuPalette.mutedInk)

            TextField("Filter branches", text: $searchText)
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
        .animation(Motion.hover, value: isSearchFocused)
        .onChange(of: isSearchFocused) { _, focused in
            if !focused && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                withAnimation(Motion.spring) {
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
                    .font(Typography.emptyTitle)
                    .typographyTracking(forSize: 18)
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

    private func cardList(snapshot: MenuBarSnapshot) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                cards(snapshot: snapshot)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(maxHeight: .infinity)
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

    /// A provider with watched projects that has not reported a poll yet has no data, and no
    /// data is not the same as no activity.
    private var isAwaitingFirstPoll: Bool {
        (!appState.watchedProjects.isEmpty && appState.poller.lastPollTime == nil)
            || (!appState.watchedVercelProjects.isEmpty && appState.vercelPoller.lastPollTime == nil)
    }

    private var latestPollTime: Date? {
        let times = [appState.poller.lastPollTime, appState.vercelPoller.lastPollTime].compactMap { $0 }
        return times.max()
    }

    private func makeSnapshot() -> MenuBarSnapshot {
        let normalizedSearchText = trimmedSearchText
        let hasSearchQuery = !normalizedSearchText.isEmpty

        guard hasSearchQuery else {
            return MenuBarSnapshot(
                hasSearchQuery: false,
                filteredPendingApprovals: appState.pendingApprovals,
                filteredCards: appState.repoCards
            )
        }

        let filteredCards: [RepoCard] = appState.repoCards.compactMap { card in
            let branches = card.branches.filter {
                branchMatchesSearch($0.branch, searchText: normalizedSearchText)
            }
            guard !branches.isEmpty else { return nil }
            return RepoCard(
                id: card.id,
                title: card.title,
                circleCI: card.circleCI,
                vercel: card.vercel,
                branches: branches
            )
        }

        return MenuBarSnapshot(
            hasSearchQuery: true,
            filteredPendingApprovals: appState.pendingApprovals.filter { approval in
                branchMatchesSearch(approval.build.branch, searchText: normalizedSearchText)
            },
            filteredCards: filteredCards
        )
    }

    @ViewBuilder
    private func pendingApprovals(_ approvals: [PendingApproval]) -> some View {
        PendingApprovalsSection(
            approvals: approvals,
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

    private func cardSection(_ card: RepoCard) -> some View {
        RepoCardSection(
            card: card,
            currentUser: appState.currentUser,
            deployedBranchesByEnv: card.circleCI.map { appState.deployedBranchesByEnv(forSlug: $0.slug) } ?? [:],
            deployingBranchesByEnv: card.circleCI.map { appState.deployingBranchesByEnv(forSlug: $0.slug) } ?? [:],
            workflowStatusByWorkflowId: appState.workflowStatusByWorkflowId,
            approvalCapableWorkflowIds: appState.approvalCapableWorkflowIds,
            armedAutoApprovalWorkflowIds: appState.armedAutoApprovalWorkflowIds,
            onRetry: { build in
                pendingAction = .retry(build)
            },
            onCancel: { build in
                pendingAction = .cancel(build)
            },
            onRedeploy: { build in
                guard let project = card.circleCI else { return }
                deployTarget = DeployTarget(project: project, branch: build.branch ?? "")
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
                deployTarget = DeployTarget(project: project)
            }
        )
    }

    @ViewBuilder
    private func cards(snapshot: MenuBarSnapshot) -> some View {
        if !snapshot.filteredPendingApprovals.isEmpty {
            pendingApprovals(snapshot.filteredPendingApprovals)
        }

        if !snapshot.filteredCards.isEmpty {
            SeparatedSections(items: snapshot.filteredCards, section: cardSection)
        } else if snapshot.hasSearchQuery {
            ProviderEmptyStateCard(
                title: "No matching results",
                message: "No branch matches “\(trimmedSearchText)”. Clear the filter to see every build and deployment.",
                icon: "magnifyingglass",
                tint: AppChrome.textMuted,
                actionTitle: "Clear filter",
                action: { searchText = "" }
            )
        } else if snapshot.filteredPendingApprovals.isEmpty {
            ProviderEmptyStateCard(
                title: isAwaitingFirstPoll ? "Loading builds" : "Waiting for the first build",
                message: isAwaitingFirstPoll
                    ? "Fetching the latest builds and deployments."
                    : "The watched projects have no recent activity. Branches show up after the next poll.",
                icon: "clock.arrow.circlepath"
            )
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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
            withAnimation(Motion.spring) {
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
        withAnimation(Motion.spring) {
            isSearchExpanded = false
        }
    }

    private func clearSearch() {
        searchText = ""
        if !isSearchFocused {
            withAnimation(Motion.spring) {
                isSearchExpanded = false
            }
        }
    }

    private func branchMatchesSearch(_ branch: String?, searchText: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        return (branch ?? "").localizedCaseInsensitiveContains(searchText)
    }

    private func openSettings() {
        AppWindowManager.dismissActiveMenuBarWindow {
            AppWindowManager.openSettings(appState)
        }
    }

    private func openBuildUrl(_ urlString: String?) {
        AppWindowManager.openFromMenu(urlString)
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

private struct UpdatePill: View {
    let version: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Update")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(AppChrome.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(AppChrome.accentSoft.opacity(isHovered ? 1.6 : 1.0))
            )
            .overlay(
                Capsule().strokeBorder(AppChrome.accent.opacity(0.25), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointingHandCursor()
        .help("Version \(version) is available - click to view the release")
        .accessibilityLabel("Update to version \(version)")
    }
}

private struct HeaderIconButton: View {
    let systemName: String
    let help: String
    let accessibilityLabel: String
    var isLoading: Bool = false
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isActive || isHovered ? AppChrome.text : AppChrome.textMuted)
                }
            }
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
