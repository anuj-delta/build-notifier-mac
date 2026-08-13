import SwiftUI

struct VercelDeploymentRow: View {
    let deployment: VercelDeployment
    let scopeSlug: String?

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusGutter

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(primaryLabel)
                        .font(Typography.rowTitle)
                        .foregroundStyle(AppChrome.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                        .shimmering(active: status.isInProgress)

                    if let sha = deployment.meta?.commitSha {
                        CommitDeploymentBadge(sha: sha, isRowHovered: isHovered) {
                            open(commitDeploymentUrl)
                        }
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 5) {
                    if let author = deployment.authorDisplayName {
                        Text(author)
                            .font(Typography.rowAuthor)
                            .foregroundStyle(AppChrome.textSecondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        Text("·")
                            .font(Typography.rowMeta)
                            .foregroundStyle(AppChrome.textMuted)
                    }

                    Text(deployment.truncatedCommitMessage)
                        .font(Typography.rowMeta)
                        .foregroundStyle(AppChrome.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(deployment.relativeTime)
                .font(Typography.rowMeta)
                .foregroundStyle(AppChrome.textMuted)
                .frame(width: RowLayout.trailingColumnWidth, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: AppChrome.radiusMedium, style: .continuous)
                .fill(isHovered ? AppChrome.rowHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .pointingHandCursor()
        .onTapGesture {
            open(branchPreviewUrl ?? commitDeploymentUrl)
        }
        .help(branchPreviewUrl == nil
              ? "Open this deployment"
              : "Open the branch preview - always the latest deploy on this branch")
    }

    private var status: RowStatus {
        RowStatus(deployment.deploymentStatus)
    }

    /// Matches `BuildRow` so CircleCI and Vercel rows share one leading status column.
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

    private var primaryLabel: String {
        if let prNumber = deployment.meta?.prNumber {
            return "PR #\(prNumber)"
        }
        if let branch = deployment.meta?.branch {
            return branch
        }
        return "Unknown ref"
    }

    private var branchPreviewUrl: String? {
        deployment.branchPreviewUrl(scopeSlug: scopeSlug)
    }

    private var commitDeploymentUrl: String {
        deployment.deploymentUrl ?? deployment.vercelDashboardUrl
    }

    private func open(_ urlString: String) {
        AppWindowManager.openFromMenu(urlString)
    }
}

/// The short commit SHA, doubling as the way into this exact deployment - the row itself opens the
/// branch preview, which moves on with every new push.
private struct CommitDeploymentBadge: View {
    let sha: String
    let isRowHovered: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(sha)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isHovered ? AppChrome.accent : AppChrome.textMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(isHovered ? AppChrome.accentSoft : AppChrome.surfaceMuted)
                        .overlay(
                            Capsule().strokeBorder(
                                isHovered ? AppChrome.accent.opacity(0.8) : AppChrome.border.opacity(0.6),
                                lineWidth: 1
                            )
                        )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .opacity(isRowHovered ? 1 : 0.85)
        .animation(Motion.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .pointingHandCursor()
        .help("Open this commit's deployment")
    }
}

struct VercelProjectSection: View {
    let project: WatchedVercelProject
    let deployments: [VercelDeployment]
    let isFiltered: Bool

    @State private var isExpanded = true

    private static let maxDeployments = 5

    /// The deployments to show: the newest N by creation time, plus the current production
    /// deployment pinned in even when a burst of preview deployments would otherwise push it
    /// past the cap - so a live prod deploy never silently drops off the list. Sorts explicitly
    /// rather than trusting the API's return order.
    private var displayedDeployments: [VercelDeployment] {
        let sorted = deployments.sorted { $0.createdAt > $1.createdAt }
        var shown = Array(sorted.prefix(Self.maxDeployments))
        if let latestProduction = sorted.first(where: { $0.isProduction }),
           !shown.contains(where: { $0.id == latestProduction.id }) {
            shown.append(latestProduction)
        }
        return shown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.spring) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    Text(project.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppChrome.text)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Text("\(displayedDeployments.count)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(AppChrome.textMuted)

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

            if isExpanded {
                if deployments.isEmpty {
                    EmptySectionNote(text: "No deployments yet")
                } else {
                    VStack(spacing: 2) {
                        ForEach(displayedDeployments) { deployment in
                            VercelDeploymentRow(deployment: deployment, scopeSlug: project.teamSlug)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }
}
