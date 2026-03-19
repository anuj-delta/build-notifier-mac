import SwiftUI

struct ProjectSection: View {
    let project: WatchedProject
    let buildsByBranch: [String: [Build]]
    let isFiltered: Bool
    let onRetry: (Build) -> Void
    let onCancel: (Build) -> Void
    let onOpen: (Build) -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    ProviderMark(style: .circleCI, color: Color.accentColor, size: 13)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text(branchCountLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(sortedBranches, id: \.self) { branch in
                        if let builds = buildsByBranch[branch], let build = builds.first {
                            BuildRow(
                                build: build,
                                onRetry: { onRetry(build) },
                                onCancel: { onCancel(build) },
                                onOpen: { onOpen(build) }
                            )
                        }
                    }
                }
            }
        }
        .padding(11)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(14)
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
    let build: Build
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            onOpen()
        } label: {
            HStack(alignment: .top, spacing: 11) {
                leadingIndicator

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(build.branch ?? "unknown")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        Text("#\(build.buildNum)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(build.truncatedSubject)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(build.relativeTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .trailing)

                actionButtons
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isHovered ? Color.accentColor.opacity(0.08) : Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
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
                .frame(width: 18, height: 18, alignment: .top)
                .padding(.top, 1)
        } else {
            Image(systemName: build.buildStatus.iconName)
                .font(.subheadline)
                .foregroundStyle(statusColor)
                .frame(width: 18, alignment: .top)
                .padding(.top, 1)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            if build.buildStatus.isFailure {
                Button {
                    onRetry()
                } label: {
                    actionLabel("Retry")
                }
                .buttonStyle(.plain)
                .help("Retry build")
            }

            if build.buildStatus.isRunning {
                Button {
                    onCancel()
                } label: {
                    actionLabel("Cancel")
                }
                .buttonStyle(.plain)
                .help("Cancel build")
            }
        }
        .frame(width: 72, alignment: .trailing)
        .opacity(isHovered && hasActions ? 1 : 0)
        .allowsHitTesting(isHovered && hasActions)
    }

    private func actionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(Capsule(style: .continuous))
    }

    private var hasActions: Bool {
        build.buildStatus.isFailure || build.buildStatus.isRunning
    }

    private var statusColor: Color {
        switch build.buildStatus {
        case .success, .fixed:
            return .green
        case .failed, .timedout, .infrastructureFail:
            return .red
        case .canceled:
            return .gray
        case .running, .notRunning, .queued, .scheduled:
            return .orange
        case .onHold:
            return .yellow
        default:
            return .gray
        }
    }
}
