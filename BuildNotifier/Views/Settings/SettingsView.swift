import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    // When presented from a menubar window, the app may be inactive and the first click
                    // can be used only to activate the app. Keep dismissal robust by updating state too.
                    appState.showingSettings = false
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // General Section
                    SettingsSection(title: "General") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Launch at login", isOn: Binding(
                                get: { LaunchAtLoginService.shared.isEnabled },
                                set: { LaunchAtLoginService.shared.isEnabled = $0 }
                            ))
                            
                            HStack {
                                Text("Refresh interval")
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { appState.preferences.pollingIntervalSeconds },
                                    set: { 
                                        appState.preferences.pollingIntervalSeconds = $0
                                        appState.savePreferences()
                                    }
                                )) {
                                    Text("30 seconds").tag(30)
                                    Text("60 seconds").tag(60)
                                    Text("2 minutes").tag(120)
                                    Text("5 minutes").tag(300)
                                }
                                .frame(width: 140)
                            }
                        }
                    }
                    
                    // Notifications Section
                    SettingsSection(title: "Notifications") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Toggle("Enable notifications", isOn: Binding(
                                    get: { appState.preferences.notificationsEnabled },
                                    set: { 
                                        appState.preferences.notificationsEnabled = $0
                                        appState.savePreferences()
                                    }
                                ))
                                .fontWeight(.medium)
                                
                                Spacer()
                                
                                Button("Test") {
                                    NotificationManager.shared.sendTestNotification()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            if appState.preferences.notificationsEnabled {
                                Divider()
                                    .padding(.vertical, 4)
                                
                                Toggle("Play sound", isOn: Binding(
                                    get: { appState.preferences.notificationSoundEnabled },
                                    set: { 
                                        appState.preferences.notificationSoundEnabled = $0
                                        appState.savePreferences()
                                    }
                                ))
                                
                                Divider()
                                    .padding(.vertical, 4)
                                
                                Toggle("Build success", isOn: Binding(
                                    get: { appState.preferences.notifyOnSuccess },
                                    set: { 
                                        appState.preferences.notifyOnSuccess = $0
                                        appState.savePreferences()
                                    }
                                ))
                                
                                Toggle("Build failure", isOn: Binding(
                                    get: { appState.preferences.notifyOnFailure },
                                    set: { 
                                        appState.preferences.notifyOnFailure = $0
                                        appState.savePreferences()
                                    }
                                ))
                                
                                Toggle("Pending approval", isOn: Binding(
                                    get: { appState.preferences.notifyOnPendingApproval },
                                    set: { 
                                        appState.preferences.notifyOnPendingApproval = $0
                                        appState.savePreferences()
                                    }
                                ))
                                
                                Toggle("Build started", isOn: Binding(
                                    get: { appState.preferences.notifyOnBuildStarted },
                                    set: { 
                                        appState.preferences.notifyOnBuildStarted = $0
                                        appState.savePreferences()
                                    }
                                ))
                            }
                        }
                    }
                    
                    // Projects Section
                    SettingsSection(title: "Watched Projects") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(appState.preferences.watchedProjects) { project in
                                WatchedProjectRow(
                                    project: project,
                                    onUpdate: { updated in
                                        appState.updateWatchedProject(updated)
                                    },
                                    onRemove: {
                                        appState.removeFromWatchlist(project)
                                    }
                                )
                            }
                            
                            Button("Add Projects...") {
                                appState.showingSettings = false
                                dismiss()
                                appState.currentScreen = .projectSelection
                                appState.stopPolling()
                                Task {
                                    await appState.loadProjects()
                                }
                            }
                            .buttonStyle(.link)
                        }
                    }
                    
                    // Account Section
                    SettingsSection(title: "Account") {
                        VStack(alignment: .leading, spacing: 12) {
                            if let user = appState.currentUser {
                                HStack {
                                    Text("Logged in as")
                                        .foregroundStyle(.secondary)
                                    Text(user.login ?? user.name ?? "Unknown")
                                        .fontWeight(.medium)
                                }
                            }
                            
                            HStack(spacing: 12) {
                                Button("Change API Token") {
                                    appState.changeToken()
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Sign Out") {
                                    appState.signOut()
                                }
                                .buttonStyle(.bordered)
                                .foregroundStyle(.red)
                            }
                        }
                    }
                }
                .padding()
                .contentShape(Rectangle())
                .onTapGesture { }
            }
            .contentShape(Rectangle())
            .onTapGesture { }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                Button("Quit CircleCI Notifier") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
            }
            .padding()
        }
        .frame(width: 400, height: 550)
        .background(Color(nsColor: .windowBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture { } // Consume clicks to prevent popover dismissal
        .onAppear {
            // Ensure the window is active so the first click interacts (not just activates).
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .onTapGesture { }
            
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .contentShape(Rectangle())
            .onTapGesture { }
        }
        .contentShape(Rectangle())
        .onTapGesture { }
    }
}

// MARK: - Watched Project Row

struct WatchedProjectRow: View {
    let project: WatchedProject
    let onUpdate: (WatchedProject) -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { project.isEnabled },
                set: { 
                    var updated = project
                    updated.isEnabled = $0
                    onUpdate(updated)
                }
            ))
            .labelsHidden()
            
            Text(project.displayName)
                .font(.subheadline)
            
            Spacer()
            
            Picker("", selection: Binding(
                get: { project.followMode },
                set: {
                    var updated = project
                    updated.followMode = $0
                    onUpdate(updated)
                }
            )) {
                ForEach(FollowMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .frame(width: 120)
            
            Button {
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
