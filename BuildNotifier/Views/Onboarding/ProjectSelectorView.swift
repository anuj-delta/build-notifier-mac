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
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                AppBrandIcon(size: 58)

                Text("Choose CircleCI projects")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Select the repositories you want to keep visible in the menu bar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                Label("Only projects you follow on CircleCI appear here.", systemImage: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Link("Follow more", destination: URL(string: "https://app.circleci.com/projects/")!)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.blue.opacity(0.08))
            .cornerRadius(10)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Filter projects", text: $searchText)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)

            Group {
                if appState.isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading projects...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredProjects.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(searchText.isEmpty ? "No projects found" : "No matches for your search")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
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
                        .padding(2)
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(14)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watching \(selectedProjects.count) of \(appState.projects.count) projects")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("You can adjust follow mode per project later in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    saveAndContinue()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedProjects.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 580, height: 600)
        .onAppear {
            initializeFromExistingWatchlist()
        }
    }

    private func initializeFromExistingWatchlist() {
        guard !hasInitialized else { return }
        hasInitialized = true

        for watched in appState.preferences.watchedProjects {
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

struct ProjectRow: View {
    let project: Project
    let isSelected: Bool
    @Binding var followMode: FollowMode
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onToggle()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if let vcsUrl = project.vcsUrl {
                    Text(vcsUrl)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.05), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}
