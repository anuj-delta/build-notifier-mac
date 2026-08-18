import SwiftUI
import UserNotifications

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case notifications
    case circleCI
    case vercel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .notifications: return "Notifications"
        case .circleCI: return "CircleCI"
        case .vercel: return "Vercel"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "App behavior, startup, and refresh settings."
        case .notifications: return "Choose which alerts appear in the menu bar."
        case .circleCI: return "Manage CircleCI account details and watched projects."
        case .vercel: return "Manage Vercel account details and watched projects."
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .notifications: return "bell.badge"
        case .circleCI: return "arrow.triangle.branch"
        case .vercel: return "triangle.fill"
        }
    }

}

struct SettingsView: View {
    @Bindable var appState: AppState
    @ObservedObject private var notificationManager = NotificationManager.shared

    @State private var selectedTab: SettingsTab = .general
    @State private var showingVercelOnboarding = false
    @State private var confirmChangeToken = false
    @State private var confirmDisconnectCircleCI = false
    @State private var confirmDisconnectVercel = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(maxHeight: .infinity)
                .background(GlassBackground(material: .sidebar, cornerRadius: 0))

            VStack(spacing: 0) {
                detailHeader

                ScrollView {
                    detailContent
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .background(GlassBackground(material: .contentBackground, cornerRadius: 0))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .background(MenuWindowConfigurator())
        .frame(minWidth: 820, minHeight: 560)
        .sheet(isPresented: $showingVercelOnboarding) {
            VercelOnboardingView()
                .environment(appState)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 11) {
                AppBrandIcon(size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Build Notifier")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppChrome.text)

                    Text("CircleCI and Vercel signals.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AppChrome.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(SettingsTab.allCases) { tab in
                    SidebarTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        action: {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                selectedTab = tab
                            }
                        }
                    )
                }
            }

            Spacer()

            VStack(spacing: 8) {
                if let update = appState.availableUpdate {
                    SidebarUpdateRow(version: update.version, destination: update.releaseURL)
                } else {
                    Text("v\(appVersion)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppChrome.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                SidebarLinkRow(
                    title: "Star on GitHub",
                    systemImage: "star",
                    destination: IntegrationHelpLinks.repository
                )
            }
        }
        .padding(20)
        .padding(.top, 24)
        .frame(width: 240)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedTab.title)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(AppChrome.text)

            Text(selectedTab.subtitle)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(AppChrome.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppChrome.separator)
                .frame(height: 1)
        }
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
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(
                title: "Behavior",
                subtitle: "Startup and polling preferences.",
                systemImage: "slider.horizontal.3"
            ) {
                SettingsToggleRow(
                    title: "Launch at login",
                    isOn: Binding(
                        get: { LaunchAtLoginService.shared.isEnabled },
                        set: { LaunchAtLoginService.shared.isEnabled = $0 }
                    )
                )

                Divider()

                SettingsPickerRow(title: "Refresh interval") {
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
                    .labelsHidden()
                    .fixedSize()
                    .frame(width: 150, alignment: .trailing)
                }
            }

            SettingsSection(
                title: "Menu Bar",
                subtitle: "The spinning icon shown while a branch is deploying.",
                systemImage: "menubar.rectangle"
            ) {
                SettingsToggleRow(
                    title: "Show deploy loader",
                    isOn: Binding(
                        get: { appState.preferences.showDeployLoader },
                        set: {
                            appState.preferences.showDeployLoader = $0
                            appState.savePreferences()
                        }
                    )
                )

                Divider()

                SettingsPickerRow(title: "Loader style") {
                    HStack(alignment: .center, spacing: 10) {
                        DeployLoaderPreview(style: appState.preferences.deployLoaderStyle)

                        Picker("", selection: Binding(
                            get: { appState.preferences.deployLoaderStyle },
                            set: {
                                appState.preferences.deployLoaderStyle = $0
                                appState.savePreferences()
                            }
                        )) {
                            ForEach(MenuBarDeployStyle.allCases, id: \.self) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .frame(width: 150, alignment: .trailing)
                    }
                }
                .disabled(!appState.preferences.showDeployLoader)
            }
        }
    }

    private var notificationsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            if notificationManager.authorizationStatus == .denied {
                SettingsSection(
                    title: "Notifications Are Off in macOS",
                    subtitle: "macOS is blocking notifications from Build Notifier, so no alerts can appear.",
                    systemImage: "bell.slash"
                ) {
                    SettingsTextRow("Open System Settings, turn on \"Allow notifications\" for Build Notifier, then come back — this screen updates when you return.")
                    Divider()
                    SettingsButtonStrip {
                        Button("Open System Settings") {
                            notificationManager.openSystemNotificationSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            } else if notificationManager.authorizationStatus == .notDetermined {
                SettingsSection(
                    title: "Allow Notifications",
                    subtitle: "macOS has not asked for notification permission yet.",
                    systemImage: "bell"
                ) {
                    SettingsTextRow("Build Notifier needs macOS permission before it can alert you about builds, approvals, and deployments.")
                    Divider()
                    SettingsButtonStrip {
                        Button("Allow Notifications") {
                            Task {
                                await notificationManager.requestAuthorization()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }

            SettingsSection(
                title: "Global",
                subtitle: "Master notification preferences.",
                systemImage: "bell.badge"
            ) {
                SettingsValueRow(
                    label: "macOS permission",
                    value: notificationManager.authorizationStatus.settingsDisplayName
                )

                Divider()

                SettingsToggleRow(
                    title: "Enable notifications",
                    isOn: Binding(
                        get: { appState.preferences.notificationsEnabled },
                        set: {
                            appState.preferences.notificationsEnabled = $0
                            appState.savePreferences()
                        }
                    ),
                    trailing: {
                        Button("Test") {
                            notificationManager.sendTestNotification()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(notificationManager.authorizationStatus == .denied)
                    }
                )

                Divider()

                SettingsToggleRow(
                    title: "Play sound",
                    isOn: Binding(
                        get: { appState.preferences.notificationSoundEnabled },
                        set: {
                            appState.preferences.notificationSoundEnabled = $0
                            appState.savePreferences()
                        }
                    )
                )
            }

            SettingsSection(
                title: "CircleCI Events",
                subtitle: "Build and approval notifications.",
                systemImage: "arrow.triangle.branch"
            ) {
                SettingsToggleRow(
                    title: "Build success",
                    isOn: Binding(
                        get: { appState.preferences.notifyOnSuccess },
                        set: {
                            appState.preferences.notifyOnSuccess = $0
                            appState.savePreferences()
                        }
                    )
                )
                Divider()
                SettingsToggleRow(
                    title: "Build failure",
                    isOn: Binding(
                        get: { appState.preferences.notifyOnFailure },
                        set: {
                            appState.preferences.notifyOnFailure = $0
                            appState.savePreferences()
                        }
                    )
                )
                Divider()
                SettingsToggleRow(
                    title: "Pending approval",
                    isOn: Binding(
                        get: { appState.preferences.notifyOnPendingApproval },
                        set: {
                            appState.preferences.notifyOnPendingApproval = $0
                            appState.savePreferences()
                        }
                    )
                )
                Divider()
                SettingsToggleRow(
                    title: "Build started",
                    isOn: Binding(
                        get: { appState.preferences.notifyOnBuildStarted },
                        set: {
                            appState.preferences.notifyOnBuildStarted = $0
                            appState.savePreferences()
                        }
                    )
                )
            }

            SettingsSection(
                title: "Vercel Events",
                subtitle: "Deployment notifications.",
                systemImage: "triangle.fill"
            ) {
                SettingsToggleRow(
                    title: "Deployment notifications",
                    isOn: Binding(
                        get: { appState.preferences.vercelNotificationsEnabled },
                        set: {
                            appState.preferences.vercelNotificationsEnabled = $0
                            appState.savePreferences()
                        }
                    )
                )
                Divider()
                SettingsToggleRow(
                    title: "Deployment ready",
                    isOn: Binding(
                        get: { appState.preferences.notifyOnDeploymentReady },
                        set: {
                            appState.preferences.notifyOnDeploymentReady = $0
                            appState.savePreferences()
                        }
                    )
                )
                .disabled(!appState.preferences.vercelNotificationsEnabled)
                Divider()
                SettingsToggleRow(
                    title: "Deployment error",
                    isOn: Binding(
                        get: { appState.preferences.notifyOnDeploymentError },
                        set: {
                            appState.preferences.notifyOnDeploymentError = $0
                            appState.savePreferences()
                        }
                    )
                )
                .disabled(!appState.preferences.vercelNotificationsEnabled)
            }

            celebrationsSection
        }
        .task {
            await notificationManager.checkAuthorizationStatus()
        }
    }

    private var celebrationsSection: some View {
        SettingsSection(
            title: "Celebrations",
            subtitle: "Confetti and sound effects for production and deployed branches, and failures.",
            systemImage: "party.popper"
        ) {
            SettingsToggleRow(
                title: "Confetti on production deploy",
                isOn: Binding(
                    get: { appState.preferences.celebrateProdSuccess },
                    set: {
                        appState.preferences.celebrateProdSuccess = $0
                        appState.savePreferences()
                    }
                ),
                trailing: {
                    Button("Test") {
                        appState.celebrate(projectLabel: "your-org/your-project", kind: .production)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            )

            Divider()

            SettingsToggleRow(
                title: "Confetti on branches I deploy",
                isOn: Binding(
                    get: { appState.preferences.celebrateDeployedBranches },
                    set: {
                        appState.preferences.celebrateDeployedBranches = $0
                        appState.savePreferences()
                    }
                )
            )

            Divider()

            SettingsPickerRow(title: "Success sound") {
                soundSelector(
                    options: CelebrationSound.successBucket,
                    rawValue: Binding(
                        get: { appState.preferences.successSound },
                        set: {
                            appState.preferences.successSound = $0
                            appState.savePreferences()
                        }
                    ),
                    fallback: .defaultSuccess
                )
            }
            .disabled(!(appState.preferences.celebrateProdSuccess || appState.preferences.celebrateDeployedBranches))

            Divider()

            SettingsToggleRow(
                title: "Play sound on failure",
                isOn: Binding(
                    get: { appState.preferences.playFailureSound },
                    set: {
                        appState.preferences.playFailureSound = $0
                        appState.savePreferences()
                    }
                )
            )

            Divider()

            SettingsPickerRow(title: "Failure sound") {
                soundSelector(
                    options: CelebrationSound.failureBucket,
                    rawValue: Binding(
                        get: { appState.preferences.failureSound },
                        set: {
                            appState.preferences.failureSound = $0
                            appState.savePreferences()
                        }
                    ),
                    fallback: .defaultFailure
                )
            }
            .disabled(!appState.preferences.playFailureSound)

            Divider()

            ProductionBranchesRow(
                branches: Binding(
                    get: { appState.preferences.productionBranches },
                    set: {
                        appState.preferences.productionBranches = $0
                        appState.savePreferences()
                    }
                )
            )
        }
    }

    private func soundSelector(
        options: [CelebrationSound],
        rawValue: Binding<String>,
        fallback: CelebrationSound
    ) -> some View {
        let selected = CelebrationSound(rawValue: rawValue.wrappedValue) ?? fallback
        return HStack(spacing: 8) {
            Picker("", selection: Binding(
                get: { selected },
                set: { rawValue.wrappedValue = $0.rawValue }
            )) {
                ForEach(options, id: \.self) { sound in
                    Text(sound.displayName).tag(sound)
                }
            }
            .labelsHidden()
            .frame(width: 170)

            Button {
                AudioPlayer.shared.preview(selected)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Preview sound")
        }
    }

    @ViewBuilder
    private var circleCITab: some View {
        if appState.hasCircleCIToken {
            VStack(alignment: .leading, spacing: 20) {
                AccountPanel(
                    provider: .circleCI,
                    accountName: appState.currentUser?.login ?? appState.currentUser?.name ?? "Unknown",
                    maskedToken: KeychainService.shared.maskedCircleCIToken() ?? "Unavailable",
                    tokenPageURL: IntegrationHelpLinks.circleCITokenPage,
                    setupGuideURL: IntegrationHelpLinks.circleCIDocs,
                    canChangeToken: true,
                    onChangeToken: { confirmChangeToken = true },
                    onDisconnect: { confirmDisconnectCircleCI = true }
                )

                SettingsSection(
                    title: "Watched Projects",
                    subtitle: "Branches you want in the menu bar.",
                    systemImage: "arrow.triangle.branch"
                ) {
                    if appState.preferences.watchedProjects.isEmpty {
                        SettingsTextRow("No CircleCI projects are being watched yet.")
                    } else {
                        ForEach(Array(appState.preferences.watchedProjects.enumerated()), id: \.element.id) { index, project in
                            WatchedProjectRow(
                                project: project,
                                onUpdate: { updated in
                                    appState.updateWatchedProject(updated)
                                },
                                onRemove: {
                                    appState.removeFromWatchlist(project)
                                }
                            )

                            if index < appState.preferences.watchedProjects.count - 1 {
                                Divider()
                            }
                        }
                    }

                    Divider()

                    SettingsButtonStrip {
                        Button("Choose CircleCI Projects…") {
                            presentCircleCIProjectSelection(refreshProjects: false)
                        }
                        .buttonStyle(.bordered)

                        Button("Refresh Followed Projects") {
                            presentCircleCIProjectSelection(refreshProjects: true)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .confirmationDialog(
                "Change your CircleCI token?",
                isPresented: $confirmChangeToken,
                titleVisibility: .visible
            ) {
                Button("Change Token") {
                    appState.changeToken()
                    AppWindowManager.closeSettings()
                    AppWindowManager.openSetup(appState)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll re-enter a token. Your watched projects are kept.")
            }
            .confirmationDialog(
                "Disconnect CircleCI?",
                isPresented: $confirmDisconnectCircleCI,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    appState.signOut()
                    AppWindowManager.closeSettings()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your token and clears your watched projects.")
            }
        } else {
            VStack(alignment: .leading, spacing: 20) {
                SettingsEmptyStateSection(
                    title: "CircleCI is not connected",
                    message: "Connect your CircleCI token to watch builds and approval jobs.",
                    buttonTitle: "Open CircleCI Setup",
                    action: {
                        appState.currentScreen = .onboarding
                        AppWindowManager.closeSettings()
                        AppWindowManager.openSetup(appState)
                    }
                )

                SettingsSection(
                    title: "Quick Links",
                    subtitle: "Open CircleCI account resources.",
                    systemImage: "link"
                ) {
                    IntegrationHelpLinkRow(
                        title: "Open CircleCI token page",
                        destination: IntegrationHelpLinks.circleCITokenPage
                    )
                    Divider()
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
                AccountPanel(
                    provider: .vercel,
                    accountName: appState.vercelUser?.username ?? appState.vercelUser?.email ?? "Unknown",
                    maskedToken: KeychainService.shared.maskedVercelToken() ?? "Unavailable",
                    tokenPageURL: IntegrationHelpLinks.vercelTokenPage,
                    setupGuideURL: IntegrationHelpLinks.vercelDocs,
                    onDisconnect: { confirmDisconnectVercel = true }
                )

                SettingsSection(
                    title: "Watched Projects",
                    subtitle: "Deployments you want in the menu bar.",
                    systemImage: "triangle.fill"
                ) {
                    if appState.preferences.watchedVercelProjects.isEmpty {
                        SettingsTextRow("No Vercel projects are being watched yet.")
                    } else {
                        ForEach(Array(appState.preferences.watchedVercelProjects.enumerated()), id: \.element.id) { index, project in
                            WatchedVercelProjectRow(
                                project: project,
                                repositoryURL: vercelProjectURL(project),
                                repositories: appState.preferences.watchedProjects,
                                onUpdate: { updated in
                                    appState.updateWatchedVercelProject(updated)
                                },
                                onRemove: {
                                    appState.removeVercelFromWatchlist(project)
                                }
                            )

                            if index < appState.preferences.watchedVercelProjects.count - 1 {
                                Divider()
                            }
                        }
                    }

                    Divider()

                    SettingsButtonStrip {
                        Button("Add Vercel Projects…") {
                            showingVercelOnboarding = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .confirmationDialog(
                "Disconnect Vercel?",
                isPresented: $confirmDisconnectVercel,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    appState.disconnectVercel()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your Vercel token and clears your watched projects.")
            }
        } else {
            VStack(alignment: .leading, spacing: 20) {
                SettingsEmptyStateSection(
                    title: "Vercel is not connected",
                    message: "Connect your Vercel account to watch preview and deployment status.",
                    buttonTitle: "Connect Vercel",
                    action: {
                        showingVercelOnboarding = true
                    }
                )

                SettingsSection(
                    title: "Quick Links",
                    subtitle: "Open Vercel account resources.",
                    systemImage: "link"
                ) {
                    IntegrationHelpLinkRow(
                        title: "Open Vercel token page",
                        destination: IntegrationHelpLinks.vercelTokenPage
                    )
                    Divider()
                    IntegrationHelpLinkRow(
                        title: "View Vercel token setup guide",
                        destination: IntegrationHelpLinks.vercelDocs
                    )
                }
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.2"
    }

    /// Vercel dashboard URL for a watched project. Owner segment is the team slug when the
    /// project is team-scoped, otherwise the connected user's handle. Nil if neither resolves,
    /// leaving the row name as plain text rather than linking somewhere wrong.
    private func vercelProjectURL(_ project: WatchedVercelProject) -> URL? {
        let owner: String?
        if let teamId = project.teamId,
           let team = appState.vercelTeams.first(where: { $0.id == teamId }) {
            owner = team.slug
        } else {
            owner = appState.vercelUser?.username
        }
        guard let owner, !owner.isEmpty else { return nil }
        return URL(string: "https://vercel.com/\(owner)/\(project.projectName)")
    }

    private func presentCircleCIProjectSelection(refreshProjects: Bool) {
        appState.showingSettings = false
        AppWindowManager.closeSettings()
        appState.currentScreen = .projectSelection
        appState.stopPolling()

        Task {
            if refreshProjects || appState.projects.isEmpty {
                await appState.loadProjects()
            }
            AppWindowManager.openSetup(appState)
        }
    }
}

private enum AccountProvider {
    case circleCI, vercel
}

/// A single quiet row for a connected integration: provider mark, account name, inline
/// connection status and masked-token fingerprint, with token help and account actions
/// tucked behind a "…" menu. Sits under a small eyebrow label rather than a full section
/// header, since the tab it lives in already names the provider.
private struct AccountPanel: View {
    let provider: AccountProvider
    let accountName: String
    let maskedToken: String
    let tokenPageURL: URL
    let setupGuideURL: URL
    var canChangeToken: Bool = false
    var onChangeToken: () -> Void = {}
    let onDisconnect: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Account")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(AppChrome.textMuted)
                .padding(.leading, 2)

            HStack(spacing: 12) {
                mark

                Text(accountName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppChrome.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                metaLine

                Spacer(minLength: 8)

                menu
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassCard()
        }
    }

    private var metaLine: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(AppChrome.success)
                .frame(width: 7, height: 7)
            Text("Connected")
                .foregroundStyle(AppChrome.textMuted)

            separatorDot
            Text(maskedToken)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(AppChrome.textSecondary)
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .font(.system(size: 12.5, weight: .regular))
        .fixedSize()
    }

    private var separatorDot: some View {
        Text("·").foregroundStyle(AppChrome.border)
    }

    @ViewBuilder private var mark: some View {
        switch provider {
        case .circleCI:
            ZStack {
                Circle()
                    .stroke(AppChrome.success, lineWidth: 2.5)
                    .frame(width: 15, height: 15)
                Circle()
                    .fill(AppChrome.success)
                    .frame(width: 4, height: 4)
            }
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppChrome.successSoft)
            )
        case .vercel:
            Image(systemName: "triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppChrome.text)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppChrome.surfaceMuted)
                )
        }
    }

    private var menu: some View {
        Menu {
            Button { openURL(tokenPageURL) } label: {
                Label("Get a token", systemImage: "arrow.up.right")
            }
            Button { openURL(setupGuideURL) } label: {
                Label("Setup guide", systemImage: "arrow.up.right")
            }
            Divider()
            if canChangeToken {
                Button { onChangeToken() } label: {
                    Label("Change token", systemImage: "key")
                }
            }
            Button(role: .destructive) { onDisconnect() } label: {
                Label("Disconnect", systemImage: "minus.circle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppChrome.textMuted)
                .frame(width: 30, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AppChrome.surfaceMuted)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(AppChrome.border, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Account actions")
    }
}

private struct SidebarUpdateRow: View {
    let version: String
    let destination: URL

    @State private var isHovered = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(destination)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(AppChrome.accent)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text("Update available")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppChrome.text)
                    Text("v\(version)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AppChrome.textMuted)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppChrome.accent)
                    .opacity(isHovered ? 1 : 0.6)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: AppChrome.radiusMedium, style: .continuous)
                    .fill(isHovered ? AppChrome.accentSoft.opacity(1.4) : AppChrome.accentSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppChrome.radiusMedium, style: .continuous)
                            .strokeBorder(AppChrome.accent.opacity(isHovered ? 0.5 : 0.3), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            switch phase {
            case .active: isHovered = true
            case .ended: isHovered = false
            }
        }
        .animation(.easeInOut(duration: 0.14), value: isHovered)
        .pointingHandCursor()
        .help("Version \(version) is available - click to view the release")
    }
}

private struct SidebarLinkRow: View {
    let title: String
    var systemImage: String = "chevron.left.forwardslash.chevron.right"
    let destination: URL

    @State private var isHovered = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(destination)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHovered ? AppChrome.accent : AppChrome.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isHovered ? AppChrome.accentSoft : AppChrome.surfaceMuted)
                    )

                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isHovered ? AppChrome.text : AppChrome.textSecondary)

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isHovered ? AppChrome.accent : AppChrome.textMuted)
                    .opacity(isHovered ? 1 : 0.5)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: AppChrome.radiusMedium, style: .continuous)
                    .fill(isHovered ? AppChrome.hover : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppChrome.radiusMedium, style: .continuous)
                            .strokeBorder(isHovered ? AppChrome.accent.opacity(0.35) : AppChrome.glassStroke, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            switch phase {
            case .active: isHovered = true
            case .ended: isHovered = false
            }
        }
        .animation(.easeInOut(duration: 0.14), value: isHovered)
        .pointingHandCursor()
        .help("Star this project on GitHub")
    }
}

private struct SidebarTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? AppChrome.accent : AppChrome.textMuted)
                    .frame(width: 20)

                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? AppChrome.text : AppChrome.textMuted)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: AppChrome.radiusSmall, style: .continuous)
                    .fill(isSelected ? AppChrome.accentSoft : (isHovered ? AppChrome.hover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            switch phase {
            case .active: isHovered = true
            case .ended: isHovered = false
            }
        }
        .pointingHandCursor()
    }
}

private struct SettingsSection<Content: View, Accessory: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accessory = accessory()
        self.content = content()
    }

    /// Icon width (18) + HStack spacing (10). Used to hang the icon into the left margin so
    /// the header text aligns with the card's row labels.
    private let iconColumnWidth: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SettingsRowIcon(systemImage: systemImage)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppChrome.text)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppChrome.textMuted)
                }

                Spacer(minLength: 12)

                accessory
            }
            // Hang the icon into the left margin so the title/subtitle line up with the row
            // labels inside the card (which sit at the card's 16pt content inset), rather than
            // being pushed right by the icon's width.
            .padding(.leading, 16 - iconColumnWidth)

            SettingsCard {
                content
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

private struct SettingsRowIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppChrome.textMuted)
            .frame(width: 18, height: 18)
    }
}

private struct SettingsToggleRow<Trailing: View>: View {
    let title: String
    @Binding var isOn: Bool
    @ViewBuilder var trailing: Trailing

    init(title: String, isOn: Binding<Bool>, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self._isOn = isOn
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppChrome.text)

            Spacer(minLength: 0)

            trailing

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(CompactSwitchToggleStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Live, animated preview of a deploy-loader style on a mini menu-bar chip. Uses
/// `TimelineView`, which animates fine in a normal window (only the status bar
/// ignores it), reusing the exact `NSImage` rendering the menu bar uses.
private struct DeployLoaderPreview: View {
    let style: MenuBarDeployStyle
    private let period: Double = 0.9

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: period) / period
            MenuBarDeployingGlyph(style: style, phase: phase)
                .foregroundStyle(.white)
        }
        .frame(width: 32, height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(red: 0.10, green: 0.12, blue: 0.24))
        )
    }
}

private struct SettingsPickerRow<Selection: View>: View {
    let title: String
    @ViewBuilder let selection: Selection

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppChrome.text)

            Spacer(minLength: 0)

            selection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct SettingsValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppChrome.textMuted)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppChrome.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .frame(maxWidth: 420, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct SettingsTextRow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(AppChrome.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }
}

private struct ProductionBranchesRow: View {
    @Binding var branches: [String]
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("Production branches")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppChrome.text)

                Spacer(minLength: 0)

                TextField("main, master", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .frame(width: 220)
                    .focused($isFocused)
                    .onSubmit(commit)
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commit() }
                    }
            }

            Text("Comma-separated. Supports a * wildcard, e.g. release/*")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(AppChrome.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear { text = branches.joined(separator: ", ") }
    }

    private func commit() {
        let parsed = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        branches = parsed
        text = parsed.joined(separator: ", ")
    }
}

private struct SettingsButtonStrip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) {
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct SettingsEmptyStateSection: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppChrome.text)

                Text(message)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppChrome.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Button(buttonTitle) {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}

private struct CompactSwitchToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(configuration.isOn ? AppChrome.accent : AppChrome.surfaceMuted)
                .frame(width: 34, height: 20)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(AppChrome.surface)
                        .frame(width: 14, height: 14)
                        .padding(3)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .stroke(configuration.isOn ? AppChrome.accent : AppChrome.border, lineWidth: 1)
                }
                .opacity(isEnabled ? 1 : 0.52)
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

struct WatchedProjectRow: View {
    let project: WatchedProject
    let onUpdate: (WatchedProject) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { project.isEnabled },
                set: {
                    var updated = project
                    updated.isEnabled = $0
                    onUpdate(updated)
                }
            ))
            .labelsHidden()
            .toggleStyle(CompactSwitchToggleStyle())

            WatchedRowNameLink(
                url: project.repositoryURL,
                openTitle: "Open repository",
                name: Text(project.orgName + "/").foregroundStyle(AppChrome.textMuted)
                    + Text(project.repoName).foregroundStyle(AppChrome.text)
            )
            .opacity(project.isEnabled ? 1 : 0.45)

            FollowModeSegmentedControl(mode: Binding(
                get: { project.followMode },
                set: {
                    var updated = project
                    updated.followMode = $0
                    onUpdate(updated)
                }
            ))
            .opacity(project.isEnabled ? 1 : 0.45)

            RowActionsMenu(openURL: project.repositoryURL, openTitle: "Open repository", onRemove: onRemove)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct WatchedVercelProjectRow: View {
    let project: WatchedVercelProject
    var repositoryURL: URL? = nil
    var repositories: [WatchedProject] = []
    let onUpdate: (WatchedVercelProject) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { project.isEnabled },
                set: {
                    var updated = project
                    updated.isEnabled = $0
                    onUpdate(updated)
                }
            ))
            .labelsHidden()
            .toggleStyle(CompactSwitchToggleStyle())

            WatchedRowNameLink(
                url: repositoryURL,
                openTitle: "Open on Vercel",
                name: Text(project.projectName).foregroundStyle(AppChrome.text)
            )
            .opacity(project.isEnabled ? 1 : 0.45)

            RepositoryLinkMenu(slug: project.repoSlug, repositories: repositories) { slug in
                var updated = project
                updated.repoSlug = slug
                onUpdate(updated)
            }
            .opacity(project.isEnabled ? 1 : 0.45)

            FollowModeSegmentedControl(mode: Binding(
                get: { project.followMode },
                set: {
                    var updated = project
                    updated.followMode = $0
                    onUpdate(updated)
                }
            ))
            .opacity(project.isEnabled ? 1 : 0.45)

            RowActionsMenu(openURL: repositoryURL, openTitle: "Open on Vercel", onRemove: onRemove)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// The project name in a watched-project row. When a URL is known the name becomes a
/// link (subtle underline on hover); otherwise it's plain text. Takes a pre-styled `Text`
/// so callers can dim the org and emphasize the repo.
private struct WatchedRowNameLink: View {
    let url: URL?
    let openTitle: String
    let name: Text

    @Environment(\.openURL) private var openURL
    @State private var hovered = false

    private var styled: some View {
        name
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)
    }

    var body: some View {
        Group {
            if let url {
                Button { openURL(url) } label: {
                    styled.underline(hovered, color: AppChrome.textMuted)
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 }
                .pointingHandCursor()
                .help(openTitle)
            } else {
                styled
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Trailing "…" menu for a watched-project row: opens the project page and removes it from
/// the watchlist. Replaces an always-visible trash icon so removal reads as deliberate.
private struct RowActionsMenu: View {
    let openURL: URL?
    let openTitle: String
    let onRemove: () -> Void

    @Environment(\.openURL) private var open

    var body: some View {
        Menu {
            if let openURL {
                Button { open(openURL) } label: {
                    Label(openTitle, systemImage: "arrow.up.right")
                }
                Divider()
            }
            Button(role: .destructive, action: onRemove) {
                Label("Remove from watchlist", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppChrome.textMuted)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Project actions")
    }
}

/// Compact two-segment mode switch for a watched-project row. Distinct in shape from the
/// row's on/off switch so "watching" and "which builds" read as separate controls.
/// The repository a Vercel project deploys, which decides the card its deployments land on.
/// Detected from the project's git link; a picker rather than a text field, so a typo cannot
/// silently unlink a project.
private struct RepositoryLinkMenu: View {
    let slug: String?
    let repositories: [WatchedProject]
    let onSelect: (String?) -> Void

    var body: some View {
        Menu {
            Button("Not linked") { onSelect(nil) }

            if !repositories.isEmpty {
                Divider()
                ForEach(repositories) { repository in
                    Button(repository.slug) { onSelect(repository.slug.lowercased()) }
                }
            }
        } label: {
            Text(slug ?? "Not linked")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(slug == nil ? AppChrome.textMuted : AppChrome.text)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 150)
        .help("The repository these deployments belong to")
    }
}

private struct FollowModeSegmentedControl: View {
    @Binding var mode: FollowMode

    var body: some View {
        HStack(spacing: 2) {
            segment(.all, label: "All")
            segment(.mine, label: "Mine")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppChrome.surfaceMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppChrome.border, lineWidth: 1)
        )
    }

    private func segment(_ value: FollowMode, label: String) -> some View {
        let isSelected = mode == value
        return Button {
            if mode != value { mode = value }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : AppChrome.textMuted)
                .frame(width: 46, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? AppChrome.accent : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension UNAuthorizationStatus {
    var settingsDisplayName: String {
        switch self {
        case .authorized: return "Allowed"
        case .provisional: return "Allowed (quietly)"
        case .denied: return "Off in System Settings"
        case .notDetermined: return "Not requested yet"
        case .ephemeral: return "Temporary"
        @unknown default: return "Unknown"
        }
    }
}
