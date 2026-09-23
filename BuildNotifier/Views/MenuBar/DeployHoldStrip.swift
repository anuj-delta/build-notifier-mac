import SwiftUI

/// An approval gate in front of a deploy workflow. These wait on every merge by design, so
/// they get a quiet line instead of the orange Pending Approvals section.
struct DeployHold: Identifiable {
    let approval: PendingApproval
    let env: DeployEnvironment
    let isSuperseded: Bool

    var id: String { approval.id }

    /// Keeps the newest build's hold for each repository, branch, and environment.
    static func newest(_ holds: [DeployHold]) -> [DeployHold] {
        func key(_ hold: DeployHold) -> String {
            "\(hold.approval.build.projectSlug)#\(hold.approval.build.branch ?? "")#\(hold.env.rawValue)"
        }
        var newest: [String: DeployHold] = [:]
        for hold in holds {
            if let kept = newest[key(hold)], kept.approval.build.buildNum >= hold.approval.build.buildNum { continue }
            newest[key(hold)] = hold
        }
        return holds.filter { newest[key($0)]?.id == $0.id }
    }
}

struct DeployHoldStrip: View {
    let holds: [DeployHold]
    let onDeploy: (PendingApproval) -> Void
    let onReject: (PendingApproval) -> Void
    let onOpen: (PendingApproval) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(holds) { hold in
                DeployHoldRow(
                    hold: hold,
                    onDeploy: { onDeploy(hold.approval) },
                    onReject: { onReject(hold.approval) },
                    onOpen: { onOpen(hold.approval) }
                )
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppChrome.separator)
                .frame(height: 1)
        }
    }
}

private struct DeployHoldRow: View {
    let hold: DeployHold
    let onDeploy: () -> Void
    let onReject: () -> Void
    let onOpen: () -> Void

    private var build: Build { hold.approval.build }

    private var summary: some View {
        let number = build.pullRequestNumber.map { " #\($0)" } ?? ""
        return HStack(spacing: 0) {
            Text("\(build.projectRepositoryName) ")
                .foregroundStyle(AppChrome.textMuted)
                .lineLimit(1)
            (Text(build.branch ?? "unknown").foregroundStyle(AppChrome.text).fontWeight(.semibold)
                + Text("\(number) held for \(hold.env.label)").foregroundStyle(AppChrome.textSecondary))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MenuPalette.approval)
                .frame(width: RowLayout.statusColumnWidth)

            Button(action: onOpen) {
                summary
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("Open in CircleCI")

            if hold.isSuperseded {
                Text("Superseded")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MenuPalette.approval)
                    .fixedSize()
                    .help("A newer \(build.branch ?? "") build exists. Deploying this hold ships older code.")
            }

            Button("Reject", action: onReject)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppChrome.textMuted)
                .pointingHandCursor()

            Button("Deploy", action: onDeploy)
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
