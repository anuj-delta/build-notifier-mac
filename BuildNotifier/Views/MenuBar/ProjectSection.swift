import SwiftUI
import BuildNotifierCore

struct ProjectSection: View {
    let project: WatchedProject
    let buildsByBranch: [String: [Build]]
    let isFiltered: Bool
    let approvalCapableWorkflowIds: Set<String>
    let armedAutoApprovalWorkflowIds: Set<String>
    let onRetry: (Build) -> Void
    let onCancel: (Build) -> Void
    let onArmAutoApprove: (Build) -> Void
    let onCancelAutoApprove: (String) -> Void
    let onOpen: (Build) -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    RepositoryPathLabel(
                        organization: project.orgName,
                        repository: project.repoName,
                        repositoryFont: .system(size: 14, weight: .semibold),
                        organizationFont: .system(size: 14, weight: .medium),
                        repositoryColor: AppChrome.text,
                        organizationColor: AppChrome.textMuted,
                        truncationMode: .middle
                    )

                    Spacer()

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
                Divider()

                VStack(spacing: 0) {
                    ForEach(Array(sortedBranches.enumerated()), id: \.element) { index, branch in
                        if let builds = buildsByBranch[branch], let build = builds.first {
                            let workflowId = build.workflows?.workflowId
                            BuildRow(
                                build: build,
                                canAutoApprove: workflowId.map { approvalCapableWorkflowIds.contains($0) } ?? false,
                                isAutoApproveArmed: workflowId.map { armedAutoApprovalWorkflowIds.contains($0) } ?? false,
                                onRetry: { onRetry(build) },
                                onCancel: { onCancel(build) },
                                onAutoApprove: { onArmAutoApprove(build) },
                                onCancelAutoApprove: {
                                    if let workflowId = build.workflows?.workflowId {
                                        onCancelAutoApprove(workflowId)
                                    }
                                },
                                onOpen: { onOpen(build) }
                            )

                            if index < sortedBranches.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppChrome.separator)
                .frame(height: 1)
        }
    }

    private var sortedBranches: [String] {
        buildsByBranch.keys.sorted { b1, b2 in
            let date1 = buildsByBranch[b1]?.first?.activityDate ?? .distantPast
            let date2 = buildsByBranch[b2]?.first?.activityDate ?? .distantPast
            return date1 > date2
        }
    }
}

struct BuildRow: View {
    private let branchLabelMaxWidth: CGFloat = 188
    private let trailingColumnWidth: CGFloat = 62
    private let trailingActionRowHeight: CGFloat = 14

    let build: Build
    let canAutoApprove: Bool
    let isAutoApproveArmed: Bool
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onAutoApprove: () -> Void
    let onCancelAutoApprove: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    leadingIndicator
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(build.branch ?? "unknown")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppChrome.text)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: branchLabelMaxWidth, alignment: .leading)

                            Text("#\(build.buildNum)")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(AppChrome.textMuted)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .monospacedDigit()

                            if isAutoApproveArmed {
                                Text("Auto")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppChrome.accent)
                            }
                        }

                        Text(build.truncatedSubject)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppChrome.textMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(build.relativeTime)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppChrome.textMuted)
                            .monospacedDigit()

                        if hasActions {
                            trailingActions
                                .frame(height: trailingActionRowHeight)
                                .opacity(isHovered || isAutoApproveArmed ? 1 : 0)
                                .allowsHitTesting(isHovered || isAutoApproveArmed)
                        }
                    }
                    .frame(width: trailingColumnWidth, alignment: .trailing)
                }
                .padding(.leading, 0)
                .padding(.trailing, 12)
                .padding(.vertical, 9)
            }
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        if build.buildStatus.isRunning {
            ProgressView()
                .controlSize(.small)
                .tint(.orange)
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: build.buildStatus.iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 14, height: 14)
        }
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
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: AppChrome.radiusMedium,
            topTrailingRadius: AppChrome.radiusMedium,
            style: .continuous
        )
        .fill(isAutoApproveArmed ? AppChrome.accentSoft : Color.clear)
        .padding(.vertical, 2)
    }

    private var hasActions: Bool {
        build.buildStatus.isFailure || build.buildStatus.isRunning || canAutoApprove || isAutoApproveArmed
    }

    private var statusColor: Color {
        switch build.buildStatus {
        case .success, .fixed:
            return .green
        case .failed, .timedout, .infrastructureFail:
            return .red
        case .canceled:
            return .gray
        case .running, .queued, .scheduled, .notRunning:
            return .orange
        case .onHold:
            return AppChrome.warning
        default:
            return .gray
        }
    }
}
