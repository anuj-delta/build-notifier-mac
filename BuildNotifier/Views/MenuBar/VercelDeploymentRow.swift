import SwiftUI

struct VercelDeploymentRow: View {
    private let labelMaxWidth: CGFloat = 220

    let deployment: VercelDeployment

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusGutter

            VStack(alignment: .leading, spacing: 4) {
                Text(primaryLabel)
                    .font(Typography.rowTitle)
                    .foregroundStyle(AppChrome.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: labelMaxWidth, alignment: .leading)
                    .shimmering(active: status.isInProgress)

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
            openDeployment()
        }
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

    private func openDeployment() {
        let urlString = deployment.deploymentUrl ?? deployment.vercelDashboardUrl
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
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
                    Text("No recent deployments")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppChrome.textMuted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                } else {
                    VStack(spacing: 2) {
                        ForEach(displayedDeployments) { deployment in
                            VercelDeploymentRow(deployment: deployment)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }
}
