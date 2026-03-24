import SwiftUI

struct VercelDeploymentRow: View {
    private let labelMaxWidth: CGFloat = 220

    let deployment: VercelDeployment

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leadingIndicator
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(primaryLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppChrome.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: labelMaxWidth, alignment: .leading)

                Text(deployment.truncatedCommitMessage)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppChrome.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Text(deployment.relativeTime)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppChrome.textMuted)
                .frame(width: 58, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isHovered ? AppChrome.hover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
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
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: deployment.deploymentStatus.iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 14, height: 14)
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

                    Image(systemName: "triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppChrome.text)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppChrome.text)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(deploymentCountLabel)
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

                if deployments.isEmpty {
                    Text("No recent deployments")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppChrome.textMuted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(deployments.prefix(5).enumerated()), id: \.element.id) { index, deployment in
                            VercelDeploymentRow(deployment: deployment)

                            if index < min(deployments.count, 5) - 1 {
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

    private var deploymentCountLabel: String {
        if isFiltered {
            return "\(deployments.count) matching deployments"
        }
        return "\(deployments.count) recent deployments"
    }
}
