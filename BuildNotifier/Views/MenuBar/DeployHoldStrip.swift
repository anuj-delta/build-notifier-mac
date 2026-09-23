import SwiftUI

/// An approval gate in front of a deploy workflow. These wait on every merge by design, so
/// they get a quiet line instead of the orange Pending Approvals section.
struct DeployHold: Identifiable {
    let approval: PendingApproval
    let env: DeployEnvironment
    let isSuperseded: Bool

    var id: String { approval.id }
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

    private var summary: Text {
        let number = build.pullRequestNumber.map { " #\($0)" } ?? ""
        return Text("\(build.projectRepositoryName) ").foregroundStyle(AppChrome.textMuted)
            + Text(build.branch ?? "unknown").foregroundStyle(AppChrome.text).fontWeight(.semibold)
            + Text("\(number) held for \(hold.env.label)").foregroundStyle(AppChrome.textSecondary)
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
                    .lineLimit(1)
                    .truncationMode(.middle)
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
