import SwiftUI

struct ProjectSelectorView: View {
    @Bindable var appState: AppState
    
    @State private var searchText = ""
    @State private var selectedProjects: Set<String> = []
    @State private var projectFollowModes: [String: FollowMode] = [:]
    @State private var hasInitialized = false
    
    var filteredProjects: [Project] {
        if searchText.isEmpty {
            return appState.projects
        }
        return appState.projects.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 8) {
                Text("Select Projects to Watch")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Choose which projects you want to receive notifications for")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                // Note about followed projects
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Only showing projects you follow on CircleCI.")
                        .font(.caption)
                    Link("Follow more", destination: URL(string: "https://app.circleci.com/projects/")!)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter projects...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            
            // Project List
            if appState.isLoading {
                ProgressView("Loading projects...")
                    .frame(maxHeight: .infinity)
            } else if filteredProjects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No projects found")
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredProjects) { project in
                            ProjectRow(
                                project: project,
                                isSelected: selectedProjects.contains(project.id),
                                followMode: Binding(
                                    get: { projectFollowModes[project.id] ?? .all },
                                    set: { projectFollowModes[project.id] = $0 }
                                ),
                                onToggle: {
                                    toggleProject(project)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
            }
            
            // Footer
            HStack {
                Text("Watching \(selectedProjects.count) of \(appState.projects.count) projects")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button("Done") {
                    saveAndContinue()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedProjects.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 550, height: 550)
        .onAppear {
            initializeFromExistingWatchlist()
        }
    }
    
    private func initializeFromExistingWatchlist() {
        guard !hasInitialized else { return }
        hasInitialized = true
        
        // Pre-select already watched projects
        for watched in appState.preferences.watchedProjects {
            // Find matching project by slug
            if let project = appState.projects.first(where: { $0.slug == watched.slug }) {
                selectedProjects.insert(project.id)
                projectFollowModes[project.id] = watched.followMode
            }
        }
    }
    
    private func toggleProject(_ project: Project) {
        if selectedProjects.contains(project.id) {
            selectedProjects.remove(project.id)
        } else {
            selectedProjects.insert(project.id)
        }
    }
    
    private func saveAndContinue() {
        // Add selected projects to watchlist
        for project in appState.projects {
            if selectedProjects.contains(project.id) {
                let followMode = projectFollowModes[project.id] ?? .all
                appState.addToWatchlist(project, followMode: followMode)
            }
        }
        
        appState.currentScreen = .main
        appState.startPolling()
    }
}

// MARK: - Project Row

struct ProjectRow: View {
    let project: Project
    let isSelected: Bool
    @Binding var followMode: FollowMode
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button {
                onToggle()
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            
            // Project Info
            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .fontWeight(.medium)
                
                if let vcsUrl = project.vcsUrl {
                    Text(vcsUrl)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Follow Mode Picker
            if isSelected {
                Picker("", selection: $followMode) {
                    ForEach(FollowMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
}
