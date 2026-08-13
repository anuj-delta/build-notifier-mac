import SwiftUI
import AppKit

extension View {
    func pointingHandCursor() -> some View {
        cursor(.pointingHand)
    }

    /// Shows `cursor` while hovered. Uses the AppKit cursor stack (`push`/`pop`) rather
    /// than `set()` so the cursor survives view redraws - otherwise an animating sibling
    /// (e.g. the shimmer) resets it every frame and the pointer flickers.
    func cursor(_ cursor: NSCursor) -> some View {
        modifier(HoverCursor(cursor: cursor))
    }
}

private struct HoverCursor: ViewModifier {
    let cursor: NSCursor

    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    guard !pushed else { return }
                    cursor.push()
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

/// A "currently deployed" / "deploying now" marker shown on a build row for one environment.
struct DeployBadge: Identifiable, Equatable {
    let env: DeployEnvironment
    let isDeploying: Bool
    var id: DeployEnvironment { env }
}

struct ProjectSection: View {
    let project: WatchedProject
    let currentUser: User?
    let branches: [BranchBuild]
    let deployedBranchesByEnv: [DeployEnvironment: String]
    let deployingBranchesByEnv: [DeployEnvironment: String]
    let workflowStatusByWorkflowId: [String: String]
    let isFiltered: Bool
    let approvalCapableWorkflowIds: Set<String>
    let armedAutoApprovalWorkflowIds: Set<String>
    let onRetry: (Build) -> Void
    let onCancel: (Build) -> Void
    let onRedeploy: (Build) -> Void
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
        branches.first?.build.vcsUrl
    }

    private func repositoryPath(highlighted: Bool) -> some View {
        Text(project.repoName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(highlighted ? AppChrome.accent : AppChrome.text)
            .lineLimit(1)
            .truncationMode(.tail)
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
                    ForEach(branches) { item in
                        let build = item.build
                        let workflowId = build.workflows?.workflowId
                        BuildRow(
                            build: build,
                            currentUser: currentUser,
                            span: item.span,
                            resolvedWorkflowStatus: workflowId.flatMap { workflowStatusByWorkflowId[$0] },
                            canAutoApprove: workflowId.map { approvalCapableWorkflowIds.contains($0) } ?? false,
                            isAutoApproveArmed: workflowId.map { armedAutoApprovalWorkflowIds.contains($0) } ?? false,
                            deployBadges: deployBadges(for: build),
                            onRetry: { onRetry(build) },
                            onCancel: { onCancel(build) },
                            onRedeploy: { onRedeploy(build) },
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
                .padding(.bottom, 4)
            }
        }
    }

    /// Deploy badges for this build's branch, in a stable order. An in-flight deploy takes
    /// precedence over a live one for the same environment so the row reads as "deploying".
    private func deployBadges(for build: Build) -> [DeployBadge] {
        guard let branch = build.branch, !branch.isEmpty else { return [] }
        return DeployEnvironment.allCases.compactMap { env in
            if deployingBranchesByEnv[env] == branch { return DeployBadge(env: env, isDeploying: true) }
            if deployedBranchesByEnv[env] == branch { return DeployBadge(env: env, isDeploying: false) }
            return nil
        }
    }
}

struct BuildRow: View {
    private let trailingActionRowHeight: CGFloat = 14

    let build: Build
    let currentUser: User?
    let span: WorkflowSpan
    let resolvedWorkflowStatus: String?
    let canAutoApprove: Bool
    let isAutoApproveArmed: Bool
    let deployBadges: [DeployBadge]
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onRedeploy: () -> Void
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
                            PullRequestBadge(
                                number: build.pullRequestNumber,
                                title: build.pullRequestTitle,
                                action: onOpenPR
                            )
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
                        if let author = build.authorDisplayName(excluding: currentUser) {
                            Text(author)
                                .font(Typography.rowAuthor)
                                .foregroundStyle(AppChrome.textSecondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)

                            Text("·")
                                .font(Typography.rowMeta)
                                .foregroundStyle(AppChrome.textMuted)
                        }

                        Text(build.pullRequestTitle ?? build.rowSubject)
                            .font(Typography.rowMeta)
                            .foregroundStyle(AppChrome.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(span.label(inProgress: status.isInProgress))
                        .font(Typography.rowMeta)
                        .foregroundStyle(AppChrome.textMuted)
                        .monospacedDigit()

                    // One second slot: the deploy badge sits here, and the hover
                    // actions swap into the same place. Stacking both would grow
                    // the row past its two text lines and leave the action button
                    // floating below the row.
                    if !deployBadges.isEmpty || hasActions {
                        ZStack(alignment: .trailing) {
                            if !deployBadges.isEmpty {
                                deployIndicator
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
                // Grows past its base width to fit multiple badges (e.g. devnet + sigma) so the
                // subject text truncates instead of being overlapped; the timestamp stays
                // right-aligned to the row edge either way.
                .frame(minWidth: RowLayout.trailingColumnWidth, alignment: .trailing)
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

    /// Prefer the authoritative v2 workflow status (matches CircleCI's UI); fall back to the
    /// v1.1 build status when v2 isn't resolved yet or reports a value we don't recognize.
    private var status: RowStatus {
        if let resolvedWorkflowStatus,
           let v2Status = RowStatus(circleCIWorkflowStatus: resolvedWorkflowStatus) {
            return v2Status
        }
        return RowStatus(build.buildStatus)
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

    private var deployIndicator: some View {
        HStack(spacing: 7) {
            ForEach(deployBadges) { badge in
                HStack(spacing: 3) {
                    Image(systemName: badge.env.badgeIcon)
                        .font(.system(size: 8, weight: .semibold))
                        .symbolEffect(.pulse, options: .repeating, isActive: badge.isDeploying)
                    Text(badge.env.label)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(badge.env.badgeColor)
                // Deploying reads as "working": a pulsing icon over a dimmed chip, so it stays
                // distinct from the solid live badge even when both envs show at once.
                .opacity(badge.isDeploying ? 0.7 : 1)
                .help(badge.isDeploying ? "Deploying to \(badge.env.label)…" : "Currently deployed to \(badge.env.label)")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var trailingActions: some View {
        HStack(spacing: 8) {
            if build.buildStatus.isFailure {
                RowActionButton(
                    systemName: "arrow.clockwise",
                    title: "Retry"
                ) {
                    onRetry()
                }
            }

            if canAutoApprove || isAutoApproveArmed {
                RowActionButton(
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

            if canRedeploy {
                RowActionButton(
                    systemName: "paperplane",
                    title: "Redeploy \(build.branch ?? "this branch")"
                ) {
                    onRedeploy()
                }
            }

            if build.buildStatus.isRunning {
                RowActionButton(
                    systemName: "xmark.circle",
                    title: "Cancel",
                    hoverTint: AppChrome.danger
                ) {
                    onCancel()
                }
            }
        }
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
        build.buildStatus.isFailure || build.buildStatus.isRunning || canAutoApprove || isAutoApproveArmed || canRedeploy
    }

    /// Actions are revealed on hover, or kept visible while auto-approve is armed. A row with
    /// no actions keeps its deploy badge on hover instead of blanking the slot.
    private var showActions: Bool {
        hasActions && (isHovered || isAutoApproveArmed)
    }

    /// v1.1 and v2 disagree for a few seconds after a workflow finishes, so both have to call it
    /// stopped before Redeploy appears beside Cancel.
    private var canRedeploy: Bool {
        status != .onHold
            && !status.isInProgress
            && !build.buildStatus.isRunning
            && !build.buildStatus.isPending
            && !(build.branch ?? "").isEmpty
    }

}

/// A row action reads as live before the click: it lights up under the pointer and dips on
/// press. The hover chip sits in the background with negative padding, so it can be larger
/// than the glyph without changing the row's height.
private struct RowActionButton: View {
    let systemName: String
    let title: String
    var tint: Color = AppChrome.textMuted
    var hoverTint: Color = AppChrome.accent
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isHovered ? hoverTint : tint)
                .frame(width: 14, height: 14)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovered ? hoverTint.opacity(0.14) : .clear)
                        .padding(-3)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(RowActionButtonStyle())
        .onHover { isHovered = $0 }
        .help(title)
        .accessibilityLabel(title)
        .animation(Motion.hover, value: isHovered)
    }
}

private struct RowActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.hover, value: configuration.isPressed)
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
    let title: String?
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
        .help(tooltip)
    }

    /// Carries the full title, because the second line of the row truncates it.
    private var tooltip: String {
        let target = number.map { "#\($0)" } ?? "pull request"
        guard let title else { return "Open \(target)" }
        return "\(target) \(title)"
    }
}
