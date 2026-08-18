import SwiftUI
import AppKit

/// A "currently deployed" / "deploying now" marker shown on a branch row for one environment.
struct DeployBadge: Identifiable, Equatable {
    let env: DeployEnvironment
    let isDeploying: Bool
    var id: DeployEnvironment { env }
}

struct BranchRow: View {
    private let trailingActionRowHeight: CGFloat = 14

    let activity: BranchActivity
    let currentUser: User?
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

    private var build: Build? { activity.build }

    private var newestDeployment: BranchDeployment? { activity.deployments.first }

    var body: some View {
        Button {
            open()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                statusGutter

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(activity.branch)
                            .font(Typography.rowTitle)
                            .foregroundStyle(AppChrome.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .shimmering(active: status.isInProgress)

                        if let build, build.pullRequestUrl != nil {
                            PullRequestBadge(
                                number: build.pullRequestNumber,
                                title: build.pullRequestTitle,
                                action: onOpenPR
                            )
                        }

                        if build != nil, !activity.deployments.isEmpty {
                            vercelChips
                        }

                        if isAutoApproveArmed {
                            Text("Auto")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppChrome.accent)
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        if !activity.branch.isEmpty {
                            CopyBranchButton(branch: activity.branch, isRowHovered: isHovered)
                        }

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 5) {
                        if let author {
                            Text(author)
                                .font(Typography.rowAuthor)
                                .foregroundStyle(AppChrome.textSecondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)

                            Text("·")
                                .font(Typography.rowMeta)
                                .foregroundStyle(AppChrome.textMuted)
                        }

                        Text(subject)
                            .font(Typography.rowMeta)
                            .foregroundStyle(AppChrome.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(timeLabel)
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

    /// The build's status when there is one, otherwise the newest deployment's. Prefer the
    /// authoritative v2 workflow status (matches CircleCI's UI); fall back to the v1.1 build
    /// status when v2 isn't resolved yet or reports a value we don't recognize.
    private var status: RowStatus {
        guard let build else {
            guard let deployment = newestDeployment?.deployment else { return .neutral }
            return RowStatus(deployment.deploymentStatus)
        }
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

    private var author: String? {
        if let build { return build.authorDisplayName(excluding: currentUser) }
        return newestDeployment?.deployment.authorDisplayName
    }

    private var subject: String {
        if let build { return build.pullRequestTitle ?? build.rowSubject }
        return newestDeployment?.deployment.truncatedCommitMessage ?? "No commit message"
    }

    private var timeLabel: String {
        if let span = activity.span { return span.label(inProgress: status.isInProgress) }
        return newestDeployment?.deployment.relativeTime ?? "unknown"
    }

    /// At most two chips, so a repository with several Vercel projects doesn't push the branch
    /// name out of the row. The rest are counted.
    private var vercelChips: some View {
        let shown = activity.deployments.prefix(2)
        let overflow = activity.deployments.count - shown.count

        return HStack(spacing: 4) {
            ForEach(shown) { item in
                VercelChip(item: item)
            }

            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppChrome.textMuted)
                    .monospacedDigit()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
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
            if let build {
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
                        title: "Redeploy \(activity.branch)"
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

            if let commitUrl {
                RowActionButton(
                    systemName: "shippingbox",
                    title: "Open this commit's deployment"
                ) {
                    AppWindowManager.openFromMenu(commitUrl)
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
        guard let build else { return commitUrl != nil }
        return build.buildStatus.isFailure
            || build.buildStatus.isRunning
            || canAutoApprove
            || isAutoApproveArmed
            || canRedeploy
            || commitUrl != nil
    }

    /// Actions are revealed on hover, or kept visible while auto-approve is armed. A row with
    /// no actions keeps its deploy badge on hover instead of blanking the slot.
    private var showActions: Bool {
        hasActions && (isHovered || isAutoApproveArmed)
    }

    /// v1.1 and v2 disagree for a few seconds after a workflow finishes, so both have to call it
    /// stopped before Redeploy appears beside Cancel.
    private var canRedeploy: Bool {
        guard let build else { return false }
        return status != .onHold
            && !status.isInProgress
            && !build.buildStatus.isRunning
            && !build.buildStatus.isPending
            && !activity.branch.isEmpty
    }

    /// The deployment of one commit, which the row itself never opens - the row opens the branch
    /// preview, which moves on with every new push.
    private var commitUrl: String? {
        newestDeployment?.deployment.deploymentUrl
    }

    private var branchPreviewUrl: String? {
        guard let deployment = newestDeployment?.deployment else { return nil }
        return deployment.branchPreviewUrl ?? deployment.deploymentUrl
    }

    private func open() {
        if let build {
            AppWindowManager.openFromMenu(build.workflowUrl ?? build.buildUrl)
            return
        }
        AppWindowManager.openFromMenu(branchPreviewUrl)
    }
}

/// One Vercel project's newest deployment on this branch: a bare colored triangle, so a row
/// carrying both providers stays scannable.
private struct VercelChip: View {
    let item: BranchDeployment

    @State private var isHovered = false

    private var status: RowStatus {
        RowStatus(item.deployment.deploymentStatus)
    }

    /// The triangle carries the state on its own, so a running deploy gets the warning color
    /// rather than the muted one `glyphColor` uses behind the spinner.
    private var tint: Color {
        switch status {
        case .success: return AppChrome.success
        case .failed: return AppChrome.danger
        case .running, .queued: return AppChrome.warning
        case .onHold, .canceled, .neutral: return AppChrome.textMuted
        }
    }

    var body: some View {
        Button(action: open) {
            Image(systemName: "triangle.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.pulse, options: .repeating, isActive: status.isInProgress)
                .frame(width: 16, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovered ? AppChrome.hover : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .onHover { isHovered = $0 }
        .pointingHandCursor()
        .help(tooltip)
        .accessibilityLabel(tooltip)
        .animation(Motion.hover, value: isHovered)
    }

    private var tooltip: String {
        let target = item.deployment.isProduction ? "production" : "preview"
        return "\(item.project.projectName) \(target) · \(item.deployment.deploymentStatus.displayName)"
            + " · \(item.deployment.relativeTime)"
    }

    private func open() {
        AppWindowManager.openFromMenu(item.deployment.branchPreviewUrl ?? item.deployment.deploymentUrl)
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
