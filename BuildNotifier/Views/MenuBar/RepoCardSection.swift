import SwiftUI

struct RepoCardSection: View {
    let card: RepoCard
    let currentUser: User?
    let deployedBranchesByEnv: [DeployEnvironment: String]
    let deployingBranchesByEnv: [DeployEnvironment: String]
    let workflowStatusByWorkflowId: [String: String]
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
        card.branches.compactMap(\.build?.vcsUrl).first
            ?? card.circleCI?.repositoryURL?.absoluteString
    }

    private func repositoryPath(highlighted: Bool) -> some View {
        Text(card.title)
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

    private func deployButton(_ project: WatchedProject) -> some View {
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

                    if let project = card.circleCI {
                        deployButton(project)
                            .opacity(isHeaderHovered ? 1 : 0)
                            .allowsHitTesting(isHeaderHovered)
                    }

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
                if let project = card.circleCI {
                    Button("Deploy a Branch…") { onDeploy(project) }
                }
                if let repoUrl {
                    Button("Open Repository on the Web") { onOpenRepo(repoUrl) }
                }
            }

            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(card.branches) { activity in
                        let workflowId = activity.build?.workflows?.workflowId
                        BranchRow(
                            activity: activity,
                            currentUser: currentUser,
                            resolvedWorkflowStatus: workflowId.flatMap { workflowStatusByWorkflowId[$0] },
                            canAutoApprove: workflowId.map { approvalCapableWorkflowIds.contains($0) } ?? false,
                            isAutoApproveArmed: workflowId.map { armedAutoApprovalWorkflowIds.contains($0) } ?? false,
                            deployBadges: deployBadges(for: activity.branch),
                            onRetry: { withBuild(activity, onRetry) },
                            onCancel: { withBuild(activity, onCancel) },
                            onRedeploy: { withBuild(activity, onRedeploy) },
                            onAutoApprove: { withBuild(activity, onArmAutoApprove) },
                            onCancelAutoApprove: {
                                if let workflowId {
                                    onCancelAutoApprove(workflowId)
                                }
                            },
                            onOpen: { withBuild(activity, onOpen) },
                            onOpenPR: { withBuild(activity, onOpenPR) }
                        )
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    private func withBuild(_ activity: BranchActivity, _ action: (Build) -> Void) {
        guard let build = activity.build else { return }
        action(build)
    }

    /// Deploy badges for a branch, in a stable order. An in-flight deploy takes precedence over
    /// a live one for the same environment so the row reads as "deploying".
    private func deployBadges(for branch: String) -> [DeployBadge] {
        guard !branch.isEmpty else { return [] }
        return DeployEnvironment.allCases.compactMap { env in
            if deployingBranchesByEnv[env] == branch { return DeployBadge(env: env, isDeploying: true) }
            if deployedBranchesByEnv[env] == branch { return DeployBadge(env: env, isDeploying: false) }
            return nil
        }
    }
}
