import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case notifications
    case circleCI
    case vercel
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .notifications: return "Notifications"
        case .circleCI: return "CircleCI"
        case .vercel: return "Vercel"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "App behavior and startup"
        case .notifications: return "Alert preferences"
        case .circleCI: return "Projects and account"
        case .vercel: return "Deployments and account"
        case .about: return "Credits and app info"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .notifications: return "bell.badge"
        case .circleCI: return "arrow.triangle.branch"
        case .vercel: return "triangle.fill"
        case .about: return "heart.text.square"
        }
    }
}

struct SettingsView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var selectedTab: SettingsTab = .general
    @State private var showingVercelOnboarding = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            VStack(spacing: 0) {
                detailHeader

                Divider()

                ScrollView {
                    detailContent
                        .padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 860, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .sheet(isPresented: $showingVercelOnboarding) {
            VercelOnboardingView()
                .environment(appState)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                AppBrandIcon(size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Build Notifier")
                        .font(.headline)
                    Text("CircleCI + Vercel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 6) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tab.systemImage)
                                .frame(width: 14)
                            Text(tab.title)
                            Spacer()
                        }
                        .font(.subheadline)
                        .fontWeight(selectedTab == tab ? .semibold : .regular)
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SettingsPill(title: "CircleCI", value: appState.hasCircleCIToken ? "On" : "Off")
                SettingsPill(title: "Vercel", value: appState.hasVercelToken ? "On" : "Off")
            }
        }
        .padding(18)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var detailHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedTab.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(selectedTab.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .general:
            generalTab
        case .notifications:
            notificationsTab
        case .circleCI:
            circleCITab
        case .vercel:
            vercelTab
        case .about:
            aboutTab
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsHeroCard()

            SettingsCard("Behavior", systemImage: "slider.horizontal.3") {
                Toggle("Launch at login", isOn: Binding(
                    get: { LaunchAtLoginService.shared.isEnabled },
                    set: { LaunchAtLoginService.shared.isEnabled = $0 }
                ))

                Divider()

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
                    .frame(width: 150)
                }
            }

            SettingsCard("Integrations", systemImage: "link") {
                SettingsAccountField(label: "CircleCI watched projects", value: "\(appState.preferences.watchedProjects.count)")
                SettingsAccountField(label: "Vercel watched projects", value: "\(appState.preferences.watchedVercelProjects.count)")
                SettingsAccountField(label: "Overall status", value: appState.overallStatus.title)
            }
        }
    }

    private var notificationsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard("Global", systemImage: "bell.badge") {
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
                }

                Divider()

                Toggle("Play sound", isOn: Binding(
                    get: { appState.preferences.notificationSoundEnabled },
                    set: {
                        appState.preferences.notificationSoundEnabled = $0
                        appState.savePreferences()
                    }
                ))
            }

            SettingsCard("CircleCI Events", systemImage: "arrow.triangle.branch") {
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

            SettingsCard("Vercel Events", systemImage: "triangle.fill") {
                Toggle("Deployment notifications", isOn: Binding(
                    get: { appState.preferences.vercelNotificationsEnabled },
                    set: {
                        appState.preferences.vercelNotificationsEnabled = $0
                        appState.savePreferences()
                    }
                ))

                Toggle("Deployment ready", isOn: Binding(
                    get: { appState.preferences.notifyOnDeploymentReady },
                    set: {
                        appState.preferences.notifyOnDeploymentReady = $0
                        appState.savePreferences()
                    }
                ))
                .disabled(!appState.preferences.vercelNotificationsEnabled)

                Toggle("Deployment error", isOn: Binding(
                    get: { appState.preferences.notifyOnDeploymentError },
                    set: {
                        appState.preferences.notifyOnDeploymentError = $0
                        appState.savePreferences()
                    }
                ))
                .disabled(!appState.preferences.vercelNotificationsEnabled)
            }
        }
    }

    @ViewBuilder
    private var circleCITab: some View {
        if appState.hasCircleCIToken {
            VStack(alignment: .leading, spacing: 20) {
                SettingsCard("Account", systemImage: "person.crop.circle") {
                    SettingsAccountField(
                        label: "Connected account",
                        value: appState.currentUser?.login ?? appState.currentUser?.name ?? "Unknown"
                    )
                    SettingsAccountField(
                        label: "Masked token",
                        value: KeychainService.shared.maskedCircleCIToken() ?? "Unavailable"
                    )
                }

                SettingsCard("Quick Links", systemImage: "link") {
                    IntegrationHelpLinkRow(
                        title: "Open CircleCI token page",
                        destination: IntegrationHelpLinks.circleCITokenPage
                    )
                    IntegrationHelpLinkRow(
                        title: "View CircleCI token setup guide",
                        destination: IntegrationHelpLinks.circleCIDocs
                    )
                }

                SettingsCard("Watched Projects", systemImage: "arrow.triangle.branch") {
                    if appState.preferences.watchedProjects.isEmpty {
                        Text("No CircleCI projects are being watched yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
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

                            if project.id != appState.preferences.watchedProjects.last?.id {
                                Divider()
                            }
                        }
                    }

                    Divider()

                    HStack(spacing: 10) {
                        Button("Choose CircleCI Projects...") {
                            presentCircleCIProjectSelection(refreshProjects: false)
                        }
                        .buttonStyle(.link)

                        Button {
                            presentCircleCIProjectSelection(refreshProjects: true)
                        } label: {
                            Label("Refresh Followed Projects", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                SettingsCard("Actions", systemImage: "key") {
                    HStack(spacing: 12) {
                        Button("Change API Token") {
                            appState.changeToken()
                            dismiss()
                            openWindow(id: "onboarding")
                            NSApplication.shared.activate(ignoringOtherApps: true)
                        }
                        .buttonStyle(.bordered)

                        Button("Sign Out") {
                            appState.signOut()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 20) {
                SettingsEmptyStateCard(
                    title: "CircleCI is not connected",
                    message: "Connect your CircleCI token to watch builds and approval jobs.",
                    buttonTitle: "Open CircleCI Setup",
                    action: {
                        appState.currentScreen = .onboarding
                        dismiss()
                        openWindow(id: "onboarding")
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                )

                SettingsCard("Quick Links", systemImage: "link") {
                    IntegrationHelpLinkRow(
                        title: "Open CircleCI token page",
                        destination: IntegrationHelpLinks.circleCITokenPage
                    )
                    IntegrationHelpLinkRow(
                        title: "View CircleCI token setup guide",
                        destination: IntegrationHelpLinks.circleCIDocs
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var vercelTab: some View {
        if appState.hasVercelToken {
            VStack(alignment: .leading, spacing: 20) {
                SettingsCard("Account", systemImage: "person.crop.circle.badge.checkmark") {
                    SettingsAccountField(
                        label: "Connected account",
                        value: appState.vercelUser?.username ?? appState.vercelUser?.email ?? "Unknown"
                    )
                    SettingsAccountField(
                        label: "Masked token",
                        value: KeychainService.shared.maskedVercelToken() ?? "Unavailable"
                    )

                    if let teamId = appState.preferences.selectedVercelTeamId, !teamId.isEmpty {
                        SettingsAccountField(label: "Team scope", value: teamId)
                    }
                }

                SettingsCard("Quick Links", systemImage: "link") {
                    IntegrationHelpLinkRow(
                        title: "Open Vercel token page",
                        destination: IntegrationHelpLinks.vercelTokenPage
                    )
                    IntegrationHelpLinkRow(
                        title: "View Vercel token setup guide",
                        destination: IntegrationHelpLinks.vercelDocs
                    )
                }

                SettingsCard("Watched Projects", systemImage: "triangle.fill") {
                    if appState.preferences.watchedVercelProjects.isEmpty {
                        Text("No Vercel projects are being watched yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.preferences.watchedVercelProjects) { project in
                            WatchedVercelProjectRow(
                                project: project,
                                onUpdate: { updated in
                                    appState.updateWatchedVercelProject(updated)
                                },
                                onRemove: {
                                    appState.removeVercelFromWatchlist(project)
                                }
                            )

                            if project.id != appState.preferences.watchedVercelProjects.last?.id {
                                Divider()
                            }
                        }
                    }

                    Divider()

                    Button("Add Vercel Projects...") {
                        showingVercelOnboarding = true
                    }
                    .buttonStyle(.link)
                }

                SettingsCard("Actions", systemImage: "bolt.horizontal") {
                    Button("Disconnect Vercel") {
                        appState.disconnectVercel()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 20) {
                SettingsEmptyStateCard(
                    title: "Vercel is not connected",
                    message: "Connect your Vercel account to watch preview and deployment status.",
                    buttonTitle: "Connect Vercel",
                    action: {
                        showingVercelOnboarding = true
                    }
                )

                SettingsCard("Quick Links", systemImage: "link") {
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
        }
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            AttributionCard()

            SettingsCard("Build", systemImage: "shippingbox") {
                SettingsAccountField(label: "Version", value: appVersion)
                SettingsAccountField(label: "Platform", value: "macOS 14+")
                SettingsAccountField(label: "Integrations", value: "CircleCI and Vercel")
            }

            SettingsCard("Actions", systemImage: "power") {
                Button("Quit Build Notifier") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private func presentCircleCIProjectSelection(refreshProjects: Bool) {
        appState.showingSettings = false
        dismiss()
        appState.currentScreen = .projectSelection
        appState.stopPolling()

        Task {
            if refreshProjects || appState.projects.isEmpty {
                await appState.loadProjects()
            }
            openWindow(id: "onboarding")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(14)
        }
    }
}

struct SettingsHeroCard: View {
    var body: some View {
        HStack(spacing: 14) {
            AppBrandIcon(size: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text("Build Notifier")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Monitor build health, approvals, and deployments without living in browser tabs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlBackgroundColor),
                            Color.accentColor.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }
}

struct SettingsPill: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct SettingsAccountField: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

struct SettingsEmptyStateCard: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            AppBrandIcon(size: 64)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Button(buttonTitle) {
                action()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 380)
    }
}

struct AttributionCard: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.pink)

            VStack(alignment: .leading, spacing: 2) {
                Text("Made with love by Anuj Sharma")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Thanks for using Build Notifier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(14)
    }
}

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
            .frame(width: 130)

            Button {
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

struct WatchedVercelProjectRow: View {
    let project: WatchedVercelProject
    let onUpdate: (WatchedVercelProject) -> Void
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

            Image(systemName: "triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(.primary)

            Text(project.displayName)
                .font(.subheadline)

            Spacer()

            Button {
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
