import SwiftUI

// MARK: - Vercel Deployment Row

struct VercelDeploymentRow: View {
    let deployment: VercelDeployment
    
    var body: some View {
        HStack(spacing: 8) {
            // Status icon
            Image(systemName: deployment.deploymentStatus.iconName)
                .foregroundColor(statusColor)
                .font(.system(size: 12))
            
            VStack(alignment: .leading, spacing: 2) {
                // Branch/PR info
                HStack(spacing: 4) {
                    if let prNumber = deployment.meta?.prNumber {
                        Text("PR #\(prNumber)")
                            .font(.system(size: 11, weight: .medium))
                    } else if let branch = deployment.meta?.branch {
                        Text(branch)
                            .font(.system(size: 11, weight: .medium))
                    } else {
                        Text("unknown")
                            .font(.system(size: 11, weight: .medium))
                    }
                    
                    Text("•")
                        .foregroundColor(.secondary)
                        .font(.system(size: 10))
                    
                    Text(deployment.relativeTime)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                // Commit message
                Text(deployment.truncatedCommitMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Status badge
            Text(deployment.deploymentStatus.displayName)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.2))
                .foregroundColor(statusColor)
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            openDeployment()
        }
    }
    
    private var statusColor: Color {
        switch deployment.deploymentStatus {
        case .ready: return .green
        case .error: return .red
        case .canceled: return .gray
        case .building, .queued, .initializing: return .yellow
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

// MARK: - Vercel Project Section

struct VercelProjectSection: View {
    let project: WatchedVercelProject
    let deployments: [VercelDeployment]
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Project header
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.primary)
                    
                    Text(project.displayName)
                        .font(.system(size: 12, weight: .semibold))
                    
                    Spacer()
                    
                    if let latest = deployments.first {
                        Image(systemName: latest.deploymentStatus.iconName)
                            .foregroundColor(latestStatusColor(latest))
                            .font(.system(size: 11))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Divider()
                    .padding(.horizontal, 8)
                
                if deployments.isEmpty {
                    Text("No recent deployments")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                } else {
                    ForEach(deployments.prefix(5)) { deployment in
                        VercelDeploymentRow(deployment: deployment)
                        
                        if deployment.id != deployments.prefix(5).last?.id {
                            Divider()
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func latestStatusColor(_ deployment: VercelDeployment) -> Color {
        switch deployment.deploymentStatus {
        case .ready: return .green
        case .error: return .red
        case .canceled: return .gray
        case .building, .queued, .initializing: return .yellow
        case .unknown: return .gray
        }
    }
}
