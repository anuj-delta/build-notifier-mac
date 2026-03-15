import SwiftUI

struct VercelOnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""
    @State private var selectedTeamId: String?
    @State private var manualTeamId = ""
    @State private var useManualTeamId = false
    @State private var step: OnboardingStep = .token
    @State private var selectedProjects: Set<String> = []

    enum OnboardingStep {
        case token
        case teamSelection
        case projectSelection
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { handleBack() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(Circle())
                .opacity(step != .token ? 1 : 0)
                .disabled(step == .token)

                Spacer()

                VStack(spacing: 2) {
                    Text(stepTitle)
                        .font(.headline)
                    Text(stepCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(Circle())
            }
            .padding(16)

            VStack(spacing: 0) {
                GeometryReader { proxy in
                    HStack(spacing: 8) {
                        stepIndicator(for: .token, label: "Token")
                        stepIndicator(for: .teamSelection, label: "Team")
                        stepIndicator(for: .projectSelection, label: "Projects")
                    }
                    .frame(width: proxy.size.width, alignment: .center)
                }
            }
            .frame(height: 24)
            .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 16) {
                    heroCard

                    switch step {
                    case .token:
                        tokenStepView
                    case .teamSelection:
                        teamSelectionView
                    case .projectSelection:
                        projectSelectionView
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }

            Divider()

            HStack(alignment: .center, spacing: 12) {
                if let error = appState.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }

                Spacer()

                if appState.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                Button(action: { handleNext() }) {
                    Text(nextButtonTitle)
                        .frame(minWidth: 88)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canProceed)
            }
            .padding(16)
        }
        .frame(width: 460, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var heroCard: some View {
        HStack(spacing: 14) {
            AppBrandIcon(size: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("Connect Vercel")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Add preview and production deployment visibility alongside your CircleCI builds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(14)
    }

    private var tokenStepView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Use a Vercel personal token with access to the projects you want to watch.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("Vercel Access Token")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                SecureField("Enter your Vercel token", text: $token)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 8) {
                    IntegrationHelpLinkRow(
                        title: "Open Vercel token page",
                        destination: IntegrationHelpLinks.vercelTokenPage
                    )

                    IntegrationHelpLinkRow(
                        title: "View Vercel token setup guide",
                        destination: IntegrationHelpLinks.vercelDocs
                    )
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
        }
    }

    private var teamSelectionView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose the team or personal scope that owns the projects you want to monitor.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                selectionCard(
                    title: "Personal Account",
                    subtitle: appState.vercelUser?.username ?? appState.vercelUser?.email,
                    isSelected: selectedTeamId == nil && !useManualTeamId
                ) {
                    selectedTeamId = nil
                    useManualTeamId = false
                }

                ForEach(appState.vercelTeams) { team in
                    selectionCard(
                        title: team.displayName,
                        subtitle: team.slug,
                        isSelected: selectedTeamId == team.id && !useManualTeamId
                    ) {
                        selectedTeamId = team.id
                        useManualTeamId = false
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enter team ID manually", isOn: $useManualTeamId)
                    .font(.subheadline)

                if useManualTeamId {
                    TextField("Team ID", text: $manualTeamId)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
        }
    }

    private var projectSelectionView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Select the Vercel projects that should appear in the menu bar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if appState.vercelProjects.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No projects found")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(30)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
            } else {
                VStack(spacing: 8) {
                    ForEach(appState.vercelProjects) { project in
                        selectionCard(
                            title: project.name,
                            subtitle: project.framework,
                            isSelected: selectedProjects.contains(project.id)
                        ) {
                            toggleProject(project)
                        }
                    }
                }
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case .token: return "Connect Vercel"
        case .teamSelection: return "Choose Team"
        case .projectSelection: return "Choose Projects"
        }
    }

    private var stepCaption: String {
        switch step {
        case .token: return "Authenticate your account"
        case .teamSelection: return "Set the project scope"
        case .projectSelection: return "Pick what to watch"
        }
    }

    private var nextButtonTitle: String {
        switch step {
        case .token: return "Connect"
        case .teamSelection: return "Next"
        case .projectSelection: return "Done"
        }
    }

    private var canProceed: Bool {
        switch step {
        case .token:
            return !token.isEmpty && !appState.isLoading
        case .teamSelection:
            return !appState.isLoading && (!useManualTeamId || !manualTeamId.isEmpty)
        case .projectSelection:
            return !selectedProjects.isEmpty && !appState.isLoading
        }
    }

    private var effectiveTeamId: String? {
        if useManualTeamId && !manualTeamId.isEmpty {
            return manualTeamId
        }
        return selectedTeamId
    }

    private func handleBack() {
        switch step {
        case .token:
            break
        case .teamSelection:
            step = .token
        case .projectSelection:
            step = .teamSelection
        }
    }

    private func handleNext() {
        switch step {
        case .token:
            Task {
                if await appState.validateVercelToken(token) {
                    await appState.loadVercelTeams()
                    step = .teamSelection
                }
            }
        case .teamSelection:
            appState.preferences.selectedVercelTeamId = effectiveTeamId
            appState.preferences.save()
            Task {
                await appState.loadVercelProjects(teamId: effectiveTeamId)
                step = .projectSelection
            }
        case .projectSelection:
            for projectId in selectedProjects {
                if let project = appState.vercelProjects.first(where: { $0.id == projectId }) {
                    appState.addVercelToWatchlist(project, teamId: effectiveTeamId)
                }
            }
            appState.startVercelPolling()
            dismiss()
        }
    }

    private func toggleProject(_ project: VercelProject) {
        if selectedProjects.contains(project.id) {
            selectedProjects.remove(project.id)
        } else {
            selectedProjects.insert(project.id)
        }
    }
    private func stepIndicator(for target: OnboardingStep, label: String) -> some View {
        let isActive = step == target
        let isCompleted = stepOrder(target) < stepOrder(step)

        return HStack(spacing: 6) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : (isActive ? "largecircle.fill.circle" : "circle"))
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(isActive || isCompleted ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((isActive ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor)))
        .cornerRadius(999)
    }

    private func stepOrder(_ step: OnboardingStep) -> Int {
        switch step {
        case .token: return 0
        case .teamSelection: return 1
        case .projectSelection: return 2
        }
    }

    private func selectionCard(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.05), lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
