import SwiftUI

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
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppChrome.textMuted)
                        .frame(width: 12)

                    ProviderMark(style: .circleCI, color: AppChrome.accent, size: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppChrome.text)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(branchCountLabel)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppChrome.textMuted)
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
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
                                    .padding(.leading, 40)
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

    private var branchCountLabel: String {
        if isFiltered {
            return "\(sortedBranches.count) matching branches"
        }
        return "\(sortedBranches.count) tracked branches"
    }
}

struct BuildRow: View {
    private let branchLabelMaxWidth: CGFloat = 188

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
                HStack(alignment: .top, spacing: 12) {
                    leadingIndicator
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 6) {
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

                        actionSlot
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(build.relativeTime)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppChrome.textMuted)
                        .frame(width: 62, alignment: .trailing)
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
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

    private var actionSlot: some View {
        HStack(spacing: 12) {
            if build.buildStatus.isFailure {
                actionButton("Retry", action: onRetry)
            }

            if canAutoApprove || isAutoApproveArmed {
                actionButton(isAutoApproveArmed ? "Cancel Auto" : "Auto-Approve") {
                    if isAutoApproveArmed {
                        onCancelAutoApprove()
                    } else {
                        onAutoApprove()
                    }
                }
            }

            if build.buildStatus.isRunning {
                actionButton("Cancel", action: onCancel)
            }
        }
        .frame(height: hasActions ? 16 : 0, alignment: .leading)
        .opacity(hasActions && (isHovered || isAutoApproveArmed) ? 1 : 0)
        .allowsHitTesting(hasActions && (isHovered || isAutoApproveArmed))
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            action()
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(AppChrome.textMuted)
        .help(title)
    }

    private var rowBackground: some View {
        (isAutoApproveArmed ? AppChrome.accentSoft : (isHovered ? AppChrome.hover : Color.clear))
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
