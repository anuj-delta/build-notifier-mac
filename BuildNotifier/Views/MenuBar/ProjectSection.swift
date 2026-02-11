import SwiftUI

struct ProjectSection: View {
    let project: WatchedProject
    let buildsByBranch: [String: [Build]]
    let onRetry: (Build) -> Void
    let onCancel: (Build) -> Void
    let onOpen: (Build) -> Void
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Project Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    
                    Text(project.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    // Status indicator
                    statusIndicator
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            
            // Builds
            if isExpanded {
                VStack(spacing: 2) {
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
        .padding(.vertical, 4)
    }
    
    private var sortedBranches: [String] {
        buildsByBranch.keys.sorted { b1, b2 in
            let date1 = buildsByBranch[b1]?.first?.activityDate ?? .distantPast
            let date2 = buildsByBranch[b2]?.first?.activityDate ?? .distantPast
            return date1 > date2  // Most recent first
        }
    }
    
    private var statusIndicator: some View {
        let allBuilds = buildsByBranch.values.flatMap { $0 }
        let hasFailure = allBuilds.contains { $0.buildStatus.isFailure }
        let hasRunning = allBuilds.contains { $0.buildStatus.isRunning }
        
        let color: Color
        let icon: String
        
        if hasFailure {
            color = .red
            icon = "xmark.circle.fill"
        } else if hasRunning {
            color = .yellow
            icon = "arrow.triangle.2.circlepath"
        } else {
            color = .green
            icon = "checkmark.circle.fill"
        }
        
        return Image(systemName: icon)
            .font(.caption)
            .foregroundStyle(color)
    }
}

// MARK: - Build Row

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
            HStack(spacing: 8) {
                // Status icon
                statusIcon
                
                // Branch & Info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(build.branch ?? "unknown")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Text("#\(build.buildNum)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(build.truncatedSubject)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Time
                Text(build.relativeTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                // Actions on hover
                if isHovered {
                    HStack(spacing: 4) {
                        // Retry button for failed builds
                        if build.buildStatus.isFailure {
                            Button {
                                showRetryConfirmation = true
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .help("Retry build")
                        }
                        
                        // Cancel button for running builds
                        if build.buildStatus.isRunning {
                            Button {
                                showCancelConfirmation = true
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .help("Cancel build")
                        }
                        
                        // External link indicator
                        Image(systemName: "arrow.up.forward")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.5) : Color.clear)
        .cornerRadius(4)
        .padding(.horizontal, 8)
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
    
    private var statusIcon: some View {
        let status = build.buildStatus
        let color: Color
        
        switch status {
        case .success, .fixed:
            color = .green
        case .failed, .timedout, .infrastructureFail:
            color = .red
        case .canceled:
            color = .gray
        case .running, .notRunning, .queued, .scheduled:
            color = .yellow
        case .onHold:
            color = .orange
        default:
            color = .gray
        }
        
        return Image(systemName: status.iconName)
            .font(.caption)
            .foregroundStyle(color)
    }
}
