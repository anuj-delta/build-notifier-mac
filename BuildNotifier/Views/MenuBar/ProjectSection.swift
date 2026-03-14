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

                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text(branchCountLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    statusBadge
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

    private var statusBadge: some View {
        let allBuilds = buildsByBranch.values.flatMap { $0 }
        let hasFailure = allBuilds.contains { $0.buildStatus.isFailure }
        let hasRunning = allBuilds.contains { $0.buildStatus.isRunning }
        let title: String
        let color: Color

        if hasFailure {
            title = "Failing"
            color = .red
        } else if hasRunning {
            title = "Running"
            color = .orange
        } else {
            title = "Passing"
            color = .green
        }

        return Text(title)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .cornerRadius(999)
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
    @State private var showRetryConfirmation = false
    @State private var showCancelConfirmation = false

    var body: some View {
        Button {
            onOpen()
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: build.buildStatus.iconName)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
                    .frame(width: 18, alignment: .top)
                    .padding(.top, 1)

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

                VStack(alignment: .trailing, spacing: 4) {
                    Text(build.relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(build.buildStatus.displayName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.12))
                        .cornerRadius(999)
                }
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
        .confirmationDialog(
            "Retry Build #\(build.buildNum)?",
            isPresented: $showRetryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Retry") {
                onRetry()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will create a new build for \(build.branch ?? "this branch").")
        }
        .confirmationDialog(
            "Cancel Build #\(build.buildNum)?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel Build", role: .destructive) {
                onCancel()
            }
            Button("Keep Running", role: .cancel) {}
        } message: {
            Text("This will stop the currently running build.")
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            if build.buildStatus.isFailure {
                Button {
                    showRetryConfirmation = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption2)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(Circle())
                .help("Retry build")
            }

            if build.buildStatus.isRunning {
                Button {
                    showCancelConfirmation = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(Circle())
                .help("Cancel build")
            }
        }
        .frame(width: 48, alignment: .trailing)
        .opacity(isHovered && hasActions ? 1 : 0)
        .allowsHitTesting(isHovered && hasActions)
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
