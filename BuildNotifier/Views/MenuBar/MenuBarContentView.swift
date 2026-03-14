import SwiftUI

struct MenuBarContentView: View {
    private let popoverWidth: CGFloat = 388
    private let buildsListMaxHeight: CGFloat = 960

    @Bindable var appState: AppState
    @State private var isRefreshing = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header

            if let error = appState.error {
                ErrorBanner(
                    message: error,
                    onRetry: { appState.retryStartup() },
                    onChangeToken: { appState.changeToken() }
                )
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }

            if appState.watchedProjects.isEmpty && appState.watchedVercelProjects.isEmpty {
                emptyState
            } else {
                buildsList
            }

            footer
        }
        .frame(width: popoverWidth)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.refreshNow()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            AppBrandIcon(size: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text("Delta Build Notifer")
                    .font(.headline)

                Text(appState.overallStatus.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    MenuBarHeaderStat(title: "CircleCI", value: "\(appState.watchedProjects.count)")
                    MenuBarHeaderStat(title: "Vercel", value: "\(appState.watchedVercelProjects.count)")
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Button {
                    withAnimation(.linear(duration: 0.8).repeatCount(3, autoreverses: false)) {
                        isRefreshing = true
                    }
                    appState.refreshNow()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                        isRefreshing = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(Circle())
                .help("Refresh now")

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(Circle())
                .help("Settings")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 8)

            AppBrandIcon(size: 62)

            VStack(spacing: 6) {
                Text("Nothing is being watched yet")
                    .font(.headline)

                Text("Add CircleCI or Vercel projects to keep recent build health in the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            HStack(spacing: 10) {
                if appState.hasCircleCIToken {
                    Button("Add CircleCI Projects") {
                        appState.currentScreen = .projectSelection
                        appState.stopPolling()
                        Task {
                            await appState.loadProjects()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button("Open Settings") {
                    openSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var buildsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if !appState.pendingApprovals.isEmpty {
                    PendingApprovalsSection(
                        approvals: appState.pendingApprovals,
                        onApprove: { approval in
                            Task { await appState.approveJob(approval) }
                        },
                        onOpen: { approval in
                            openBuildUrl(approval.build.workflowUrl ?? approval.build.buildUrl)
                        }
                    )
                }

                if !appState.groupedBuilds.isEmpty {
                    PopoverSectionHeader(
                        title: "CircleCI",
                        subtitle: "Recent builds and approvals",
                        systemImage: "arrow.triangle.branch"
                    )

                    ForEach(appState.groupedBuilds, id: \.project.id) { item in
                        ProjectSection(
                            project: item.project,
                            buildsByBranch: item.builds,
                            onRetry: { build in
                                Task { await appState.retryBuild(build) }
                            },
                            onCancel: { build in
                                Task { await appState.cancelBuild(build) }
                            },
                            onOpen: { build in
                                openBuildUrl(build.workflowUrl ?? build.buildUrl)
                            }
                        )
                    }
                }

                if !appState.watchedVercelProjects.isEmpty {
                    PopoverSectionHeader(
                        title: "Vercel",
                        subtitle: "Watched deployments",
                        systemImage: "triangle.fill"
                    )

                    ForEach(appState.watchedVercelProjects) { project in
                        let deployments = appState.deploymentsByProject[project.id] ?? []
                        VercelProjectSection(project: project, deployments: deployments)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(minHeight: 360, maxHeight: buildsListMaxHeight)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let lastPoll = latestPollTime {
                Label("Updated \(lastPoll.formatted(.relative(presentation: .named)))", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var latestPollTime: Date? {
        let times = [appState.poller.lastPollTime, appState.vercelPoller.lastPollTime].compactMap { $0 }
        return times.max()
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func openBuildUrl(_ urlString: String?) {
        guard let urlString, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct MenuBarHeaderStat: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(999)
    }
}

struct PopoverSectionHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

struct ErrorBanner: View {
    let message: String
    let onRetry: () -> Void
    let onChangeToken: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button("Retry") {
                    onRetry()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Change Token") {
                    onChangeToken()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(12)
    }
}

struct PendingApprovalsSection: View {
    let approvals: [PendingApproval]
    let onApprove: (PendingApproval) -> Void
    let onOpen: (PendingApproval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Pending Approvals", systemImage: "pause.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)

                Spacer()

                Text("\(approvals.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.16))
                    .cornerRadius(999)
            }

            ForEach(approvals) { approval in
                ApprovalRow(
                    approval: approval,
                    onApprove: { onApprove(approval) },
                    onOpen: { onOpen(approval) }
                )
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.06))
        .cornerRadius(14)
    }
}

struct ApprovalRow: View {
    let approval: PendingApproval
    let onApprove: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(approval.build.projectSlug)
                    .font(.caption)
                    .fontWeight(.semibold)

                Text("\(approval.jobName) • \(approval.build.branch ?? "unknown")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Approve") {
                onApprove()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)

            Button {
                onOpen()
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.plain)
            .help("Open in browser")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(10)
    }
}
