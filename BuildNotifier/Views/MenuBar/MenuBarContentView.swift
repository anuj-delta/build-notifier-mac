import SwiftUI

struct MenuBarContentView: View {
    @Bindable var appState: AppState
    @State private var isRefreshing = false
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("CircleCI Builds")
                    .font(.headline)
                
                Spacer()
                
                // Refresh button
                Button {
                    withAnimation(.linear(duration: 0.8).repeatCount(3, autoreverses: false)) {
                        isRefreshing = true
                    }
                    appState.refreshNow()
                    // Reset after animation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                        isRefreshing = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                }
                .buttonStyle(.plain)
                .help("Refresh now")
                
                // Settings button
                Button {
                    openWindow(id: "settings")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            if let error = appState.error {
                ErrorBanner(
                    message: error,
                    onRetry: { appState.retryStartup() },
                    onChangeToken: { appState.changeToken() }
                )
                Divider()
            }
            
            // Content
            if appState.watchedProjects.isEmpty {
                emptyState
            } else {
                buildsList
            }
            
            Divider()
            
            // Footer
            footer
        }
        .frame(width: 360)
        .onAppear {
            appState.refreshNow()
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            
            Text("No projects watched")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button("Add Projects") {
                appState.currentScreen = .projectSelection
                appState.stopPolling()
                Task {
                    await appState.loadProjects()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
    
    // MARK: - Builds List
    
    private var buildsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Pending Approvals Section
                if !appState.pendingApprovals.isEmpty {
                    PendingApprovalsSection(
                        approvals: appState.pendingApprovals,
                        onApprove: { approval in
                            Task {
                                await appState.approveJob(approval)
                            }
                        },
                        onOpen: { approval in
                            openBuildUrl(approval.build.workflowUrl ?? approval.build.buildUrl)
                        }
                    )
                    
                    Divider()
                        .padding(.vertical, 8)
                }
                
                // Projects
                ForEach(appState.groupedBuilds, id: \.project.id) { item in
                    ProjectSection(
                        project: item.project,
                        buildsByBranch: item.builds,
                        onRetry: { build in
                            Task {
                                await appState.retryBuild(build)
                            }
                        },
                        onCancel: { build in
                            Task {
                                await appState.cancelBuild(build)
                            }
                        },
                        onOpen: { build in
                            openBuildUrl(build.workflowUrl ?? build.buildUrl)
                        }
                    )
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 400)
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            if let lastPoll = appState.poller.lastPollTime {
                Text("Updated \(lastPoll.formatted(.relative(presentation: .named)))")
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
        .padding(.vertical, 8)
    }
    
    // MARK: - Helpers
    
    private func openBuildUrl(_ urlString: String?) {
        guard let urlString = urlString, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.yellow.opacity(0.12))
    }
}

// MARK: - Pending Approvals Section

struct PendingApprovalsSection: View {
    let approvals: [PendingApproval]
    let onApprove: (PendingApproval) -> Void
    let onOpen: (PendingApproval) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Text("Pending Approvals")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(approvals.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            
            ForEach(approvals) { approval in
                ApprovalRow(
                    approval: approval,
                    onApprove: { onApprove(approval) },
                    onOpen: { onOpen(approval) }
                )
            }
        }
    }
}

struct ApprovalRow: View {
    let approval: PendingApproval
    let onApprove: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(approval.build.projectSlug)
                    .font(.caption)
                    .fontWeight(.medium)

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
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(6)
        .padding(.horizontal, 8)
    }
}
