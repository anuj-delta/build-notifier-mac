import SwiftUI

struct VercelDeploymentRow: View {
    let deployment: VercelDeployment

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            leadingIndicator

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(primaryLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(deployment.relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(deployment.truncatedCommitMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(deployment.relativeTime)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture {
            openDeployment()
        }
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        if deployment.deploymentStatus.isRunning {
            ProgressView()
                .controlSize(.small)
                .tint(.orange)
                .frame(width: 18, height: 18, alignment: .top)
                .padding(.top, 1)
        } else {
            Image(systemName: deployment.deploymentStatus.iconName)
                .font(.subheadline)
                .foregroundStyle(statusColor)
                .frame(width: 18, alignment: .top)
                .padding(.top, 1)
        }
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

    private var statusColor: Color {
        switch deployment.deploymentStatus {
        case .ready: return .green
        case .error: return .red
        case .canceled: return .gray
        case .building, .queued, .initializing: return .orange
        case .unknown: return .gray
        }
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

                    Image(systemName: "triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text(deploymentCountLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if deployments.isEmpty {
                    Text("No recent deployments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .cornerRadius(12)
                } else {
                    VStack(spacing: 6) {
                        ForEach(deployments.prefix(5)) { deployment in
                            VercelDeploymentRow(deployment: deployment)
                        }
                    }
                }
            }
        }
        .padding(11)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(14)
    }

    private var deploymentCountLabel: String {
        if isFiltered {
            return "\(deployments.count) matching deployments"
        }
        return "\(deployments.count) recent deployments"
    }

}
