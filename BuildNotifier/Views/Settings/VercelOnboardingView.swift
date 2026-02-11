import SwiftUI

// MARK: - Vercel Onboarding View

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
            // Header
            HStack {
                Button(action: { handleBack() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .opacity(step != .token ? 1 : 0)
                .disabled(step == .token)
                
                Spacer()
                
                Text(stepTitle)
                    .font(.headline)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 16) {
                    switch step {
                    case .token:
                        tokenStepView
                    case .teamSelection:
                        teamSelectionView
                    case .projectSelection:
                        projectSelectionView
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                if let error = appState.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
                
                Spacer()
                
                if appState.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                
                Button(action: { handleNext() }) {
                    Text(nextButtonTitle)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed)
            }
            .padding()
        }
        .frame(width: 400, height: 500)
    }
    
    // MARK: - Step Views
    
    private var tokenStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect your Vercel account to track deployments.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Vercel Access Token")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                SecureField("Enter your Vercel token", text: $token)
                    .textFieldStyle(.roundedBorder)
                
                Button(action: { openTokenPage() }) {
                    HStack(spacing: 4) {
                        Text("Get a token from Vercel")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.caption)
                }
                .buttonStyle(.link)
            }
            
            Spacer()
        }
    }
    
    private var teamSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select a team or use your personal account.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                // Personal account option
                Button(action: { selectedTeamId = nil; useManualTeamId = false }) {
                    HStack {
                        Image(systemName: selectedTeamId == nil && !useManualTeamId ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedTeamId == nil && !useManualTeamId ? .accentColor : .secondary)
                        
                        VStack(alignment: .leading) {
                            Text("Personal Account")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if let user = appState.vercelUser {
                                Text(user.username ?? user.email ?? "")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                // Teams
                ForEach(appState.vercelTeams) { team in
                    Button(action: { selectedTeamId = team.id; useManualTeamId = false }) {
                        HStack {
                            Image(systemName: selectedTeamId == team.id ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedTeamId == team.id ? .accentColor : .secondary)
                            
                            VStack(alignment: .leading) {
                                Text(team.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(team.slug)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                
                Divider()
                    .padding(.vertical, 8)
                
                // Manual team ID
                Toggle(isOn: $useManualTeamId) {
                    Text("Enter team ID manually")
                        .font(.subheadline)
                }
                
                if useManualTeamId {
                    TextField("Team ID", text: $manualTeamId)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            Spacer()
        }
    }
    
    private var projectSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select projects to watch for deployments.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if appState.vercelProjects.isEmpty {
                VStack {
                    Spacer()
                    Text("No projects found")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(appState.vercelProjects) { project in
                        Button(action: { toggleProject(project) }) {
                            HStack {
                                Image(systemName: selectedProjects.contains(project.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedProjects.contains(project.id) ? .accentColor : .secondary)
                                
                                VStack(alignment: .leading) {
                                    Text(project.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    if let framework = project.framework {
                                        Text(framework)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var stepTitle: String {
        switch step {
        case .token: return "Connect Vercel"
        case .teamSelection: return "Select Team"
        case .projectSelection: return "Select Projects"
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
    
    // MARK: - Actions
    
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
    
    private func openTokenPage() {
        if let url = URL(string: "https://vercel.com/account/tokens") {
            NSWorkspace.shared.open(url)
        }
    }
}
