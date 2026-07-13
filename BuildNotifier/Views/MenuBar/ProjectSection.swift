import SwiftUI
import AppKit

extension View {
    /// Shows the pointing-hand cursor while hovered. Uses the AppKit cursor stack
    /// (`push`/`pop`) rather than `set()` so the cursor survives view redraws -
    /// otherwise an animating sibling (e.g. the shimmer) resets it every frame and
    /// the pointer flickers.
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursor())
    }
}

private struct PointingHandCursor: ViewModifier {
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    guard !pushed else { return }
                    NSCursor.pointingHand.push()
                    pushed = true
                } else {
                    guard pushed else { return }
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onDisappear {
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}

struct ProjectSection: View {
    let project: WatchedProject
    let buildsByBranch: [String: [Build]]
    let deployedBranch: String?
    let isFiltered: Bool
    let approvalCapableWorkflowIds: Set<String>
    let armedAutoApprovalWorkflowIds: Set<String>
    let onRetry: (Build) -> Void
    let onCancel: (Build) -> Void
    let onArmAutoApprove: (Build) -> Void
    let onCancelAutoApprove: (String) -> Void
    let onOpen: (Build) -> Void
    let onOpenPR: (Build) -> Void
    let onOpenRepo: (String) -> Void
    let onDeploy: (WatchedProject) -> Void

    @State private var isExpanded = true
    @State private var isRepoLinkHovered = false
    @State private var isHeaderHovered = false
    @State private var isDeployHovered = false

    private var repoUrl: String? {
        buildsByBranch.values.first?.first?.vcsUrl
    }

    private func repositoryPath(highlighted: Bool) -> some View {
        RepositoryPathLabel(
            organization: project.orgName,
            repository: project.repoName,
            repositoryFont: .system(size: 14, weight: .semibold),
            organizationFont: .system(size: 14, weight: .medium),
            repositoryColor: highlighted ? AppChrome.accent : AppChrome.text,
            organizationColor: highlighted ? AppChrome.accent.opacity(0.7) : AppChrome.textMuted,
            truncationMode: .middle
        )
    }

    private func repositoryLink(_ repoUrl: String) -> some View {
        Button {
            onOpenRepo(repoUrl)
        } label: {
            HStack(alignment: .center, spacing: 5) {
                repositoryPath(highlighted: isRepoLinkHovered)

                if isRepoLinkHovered {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppChrome.accent)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isRepoLinkHovered = hovering
        }
        .pointingHandCursor()
        .help("Open repository on the web")
        .animation(Motion.hover, value: isRepoLinkHovered)
    }

    private var deployButton: some View {
        Button {
            onDeploy(project)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text("Deploy")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isDeployHovered ? AppChrome.accent : AppChrome.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isDeployHovered ? AppChrome.accentSoft : Color.clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isDeployHovered = hovering
        }
        .pointingHandCursor()
        .help("Deploy a branch to devnet")
        .animation(Motion.hover, value: isDeployHovered)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.spring) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 6) {
                    if let repoUrl {
                        repositoryLink(repoUrl)
                            .layoutPriority(1)
                    } else {
                        repositoryPath(highlighted: false)
                            .layoutPriority(1)
                    }

                    Spacer(minLength: 6)

                    deployButton
                        .opacity(isHeaderHovered ? 1 : 0)
                        .allowsHitTesting(isHeaderHovered)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppChrome.textMuted)
                        .frame(width: 12, height: 12)
                }
                .padding(.leading, 0)
                .padding(.trailing, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHeaderHovered = hovering
            }
            .animation(Motion.hover, value: isHeaderHovered)
            .contextMenu {
                Button("Deploy a Branch…") { onDeploy(project) }
                if let repoUrl {
                    Button("Open Repository on the Web") { onOpenRepo(repoUrl) }
                }
            }

            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(Array(sortedBranches.enumerated()), id: \.element) { index, branch in
                        if let builds = buildsByBranch[branch], let build = builds.first {
                            let workflowId = build.workflows?.workflowId
                            BuildRow(
                                build: build,
                                canAutoApprove: workflowId.map { approvalCapableWorkflowIds.contains($0) } ?? false,
                                isAutoApproveArmed: workflowId.map { armedAutoApprovalWorkflowIds.contains($0) } ?? false,
                                isDevnetDeployed: deployedBranch.map { !$0.isEmpty && build.branch == $0 } ?? false,
                                onRetry: { onRetry(build) },
                                onCancel: { onCancel(build) },
                                onAutoApprove: { onArmAutoApprove(build) },
                                onCancelAutoApprove: {
                                    if let workflowId = build.workflows?.workflowId {
                                        onCancelAutoApprove(workflowId)
                                    }
                                },
                                onOpen: { onOpen(build) },
                                onOpenPR: { onOpenPR(build) }
                            )
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    private var sortedBranches: [String] {
        buildsByBranch.keys.sorted { b1, b2 in
            let date1 = buildsByBranch[b1]?.compactMap { $0.activityDate }.max() ?? .distantPast
            let date2 = buildsByBranch[b2]?.compactMap { $0.activityDate }.max() ?? .distantPast
            return date1 > date2
        }
    }
}

struct BuildRow: View {
    private let trailingActionRowHeight: CGFloat = 14

    let build: Build
    let canAutoApprove: Bool
    let isAutoApproveArmed: Bool
    let isDevnetDeployed: Bool
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onAutoApprove: () -> Void
    let onCancelAutoApprove: () -> Void
    let onOpen: () -> Void
    let onOpenPR: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            onOpen()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                statusGutter

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(build.branch ?? "unknown")
                            .font(Typography.rowTitle)
                            .foregroundStyle(AppChrome.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .shimmering(active: status.isInProgress)

                        if build.pullRequestUrl != nil {
                            PullRequestBadge(number: build.pullRequestNumber, action: onOpenPR)
                        }

                        if isAutoApproveArmed {
                            Text("Auto")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppChrome.accent)
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        if let branch = build.branch, !branch.isEmpty {
                            CopyBranchButton(branch: branch, isRowHovered: isHovered)
                        }

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 5) {
                        if let author = build.authorDisplayName {
                            Text(author)
                                .font(Typography.rowAuthor)
                                .foregroundStyle(AppChrome.textSecondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)

                            Text("·")
                                .font(Typography.rowMeta)
                                .foregroundStyle(AppChrome.textMuted)
                        }

                        Text(build.truncatedSubject)
                            .font(Typography.rowMeta)
                            .foregroundStyle(AppChrome.textMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(build.relativeTime)
                        .font(Typography.rowMeta)
                        .foregroundStyle(AppChrome.textMuted)
                        .monospacedDigit()

                    // One second slot: the devnet badge sits here, and the hover
                    // actions swap into the same place. Stacking both would grow
                    // the row past its two text lines and leave the action button
                    // floating below the row.
                    if isDevnetDeployed || hasActions {
                        ZStack(alignment: .trailing) {
                            if isDevnetDeployed {
                                devnetIndicator
                                    .opacity(showActions ? 0 : 1)
                            }
                            if hasActions {
                                trailingActions
                                    .frame(height: trailingActionRowHeight)
                                    .opacity(showActions ? 1 : 0)
                                    .allowsHitTesting(showActions)
                            }
                        }
                        .animation(Motion.hover, value: showActions)
                    }
                }
                .frame(width: RowLayout.trailingColumnWidth, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .pointingHandCursor()
    }

    private var status: RowStatus {
        RowStatus(build.buildStatus)
    }

    /// Fixed-width leading column so status glyphs line up across every row and
    /// the list can be scanned pass/fail at a glance. Nudged down to sit on the
    /// branch line's cap height.
    private var statusGutter: some View {
        Group {
            if status.isInProgress {
                RunningSpinner()
            } else {
                StatusGlyph(status: status)
            }
        }
        .frame(width: RowLayout.statusColumnWidth, alignment: .center)
        .padding(.top, 1)
    }

    private var devnetIndicator: some View {
        HStack(spacing: 3) {
            Image(systemName: "hexagon.fill")
                .font(.system(size: 8, weight: .semibold))
            Text("devnet")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(AppChrome.deploy)
        .fixedSize(horizontal: true, vertical: false)
        .help("Currently deployed to devnet")
    }

    private var trailingActions: some View {
        HStack(spacing: 8) {
            if build.buildStatus.isFailure {
                actionIconButton(
                    systemName: "arrow.clockwise",
                    title: "Retry"
                ) {
                    onRetry()
                }
            }

            if canAutoApprove || isAutoApproveArmed {
                actionIconButton(
                    systemName: isAutoApproveArmed ? "checkmark.circle.fill" : "checkmark.circle",
                    title: isAutoApproveArmed ? "Cancel Auto-Approve" : "Auto-Approve",
                    tint: isAutoApproveArmed ? AppChrome.accent : AppChrome.textMuted
                ) {
                    if isAutoApproveArmed {
                        onCancelAutoApprove()
                    } else {
                        onAutoApprove()
                    }
                }
            }

            if build.buildStatus.isRunning {
                actionIconButton(
                    systemName: "xmark.circle",
                    title: "Cancel",
                    tint: AppChrome.textMuted
                ) {
                    onCancel()
                }
            }
        }
    }

    private func actionIconButton(
        systemName: String,
        title: String,
        tint: Color = AppChrome.textMuted,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: AppChrome.radiusMedium, style: .continuous)
            .fill(rowFill)
    }

    private var rowFill: Color {
        if isAutoApproveArmed { return AppChrome.accentSoft }
        return isHovered ? AppChrome.rowHover : Color.clear
    }

    private var hasActions: Bool {
        build.buildStatus.isFailure || build.buildStatus.isRunning || canAutoApprove || isAutoApproveArmed
    }

    /// Actions are revealed on hover, or kept visible while auto-approve is armed.
    private var showActions: Bool {
        isHovered || isAutoApproveArmed
    }

}

private struct CopyBranchButton: View {
    let branch: String
    let isRowHovered: Bool

    @State private var isHovered = false
    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            ZStack {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(AppChrome.textMuted)
                    .opacity(copied ? 0 : 1)
                Image(systemName: "checkmark")
                    .foregroundStyle(AppChrome.accent)
                    .opacity(copied ? 1 : 0)
            }
            .font(.system(size: 10, weight: .semibold))
            .frame(width: 18, height: 18)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? AppChrome.hover : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(width: 18, height: 18)
        .opacity(isRowHovered || copied ? 1 : 0)
        .allowsHitTesting(isRowHovered || copied)
        .onHover { hovering in
            isHovered = hovering
        }
        .pointingHandCursor()
        .help(copied ? "Copied" : "Copy branch name")
        .animation(.easeInOut(duration: 0.12), value: copied)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(branch, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            copied = false
        }
    }
}

private struct PullRequestBadge: View {
    let number: Int?
    let action: () -> Void

    @State private var isHovered = false

    // Lucide "git-pull-request" glyph, bundled as a single vector PDF.
    private static let icon: NSImage? = {
        guard let url = Bundle.appResources.url(forResource: "git-pull-request", withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    @ViewBuilder
    private var iconView: some View {
        if let icon = Self.icon {
            Image(nsImage: icon)
                .resizable()
                .renderingMode(.template)
                .frame(width: 11, height: 11)
        } else {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10, weight: .semibold))
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                iconView
                Text(number.map { "#\($0)" } ?? "PR")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
                .foregroundStyle(AppChrome.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(AppChrome.accentSoft.opacity(isHovered ? 1.6 : 1))
                        .overlay(
                            Capsule().strokeBorder(AppChrome.accent.opacity(isHovered ? 0.8 : 0), lineWidth: 1)
                        )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .onHover { hovering in
            isHovered = hovering
        }
        .pointingHandCursor()
        .help(number.map { "Open pull request #\($0)" } ?? "Open pull request")
    }
}
