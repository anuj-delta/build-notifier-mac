import SwiftUI
import UserNotifications

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
        case .general: return "App behavior, startup, and refresh settings."
        case .notifications: return "Choose which alerts appear in the menu bar."
        case .circleCI: return "Manage CircleCI account details and watched projects."
        case .vercel: return "Manage Vercel account details and watched projects."
        case .about: return "Version details and app actions."
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .notifications: return "bell.badge"
        case .circleCI: return "arrow.triangle.branch"
        case .vercel: return "triangle.fill"
        case .about: return "info.circle"
        }
    }

}

struct SettingsView: View {
    @Bindable var appState: AppState
    @ObservedObject private var notificationManager = NotificationManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var selectedTab: SettingsTab = .general
    @State private var showingVercelOnboarding = false

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
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
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

            VStack(alignment: .leading, spacing: 10) {
                Text("Connected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppChrome.textMuted)

                VStack(spacing: 2) {
                    SidebarStatusRow(title: "CircleCI", isActive: appState.hasCircleCIToken)
                    SidebarStatusRow(title: "Vercel", isActive: appState.hasVercelToken)
                }
            }

            SidebarLinkRow(title: "View on GitHub", destination: IntegrationHelpLinks.repository)
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
        case .about:
            aboutTab
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
                    .frame(width: 150)
                }
            }

            SettingsSection(
                title: "Overview",
                subtitle: "Current integration and watch state.",
                systemImage: "rectangle.3.group"
            ) {
                SettingsValueRow(label: "CircleCI watched projects", value: "\(appState.preferences.watchedProjects.count)")
                Divider()
                SettingsValueRow(label: "Vercel watched projects", value: "\(appState.preferences.watchedVercelProjects.count)")
                Divider()
                SettingsValueRow(label: "Overall status", value: appState.overallStatus.title)
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
        }
        .task {
            await notificationManager.checkAuthorizationStatus()
        }
    }

    @ViewBuilder
    private var circleCITab: some View {
        if appState.hasCircleCIToken {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection(
                    title: "Account",
                    subtitle: "CircleCI connection details.",
                    systemImage: "person.crop.circle"
                ) {
                    SettingsValueRow(
                        label: "Connected account",
                        value: appState.currentUser?.login ?? appState.currentUser?.name ?? "Unknown"
                    )
                    Divider()
                    SettingsValueRow(
                        label: "Masked token",
                        value: KeychainService.shared.maskedCircleCIToken() ?? "Unavailable"
                    )
                }

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

                SettingsSection(
                    title: "Actions",
                    subtitle: "Token and account actions.",
                    systemImage: "key"
                ) {
                    SettingsButtonStrip {
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
                        .tint(.red)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 20) {
                SettingsEmptyStateSection(
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
                SettingsSection(
                    title: "Account",
                    subtitle: "Vercel connection details.",
                    systemImage: "person.crop.circle.badge.checkmark"
                ) {
                    SettingsValueRow(
                        label: "Connected account",
                        value: appState.vercelUser?.username ?? appState.vercelUser?.email ?? "Unknown"
                    )
                    Divider()
                    SettingsValueRow(
                        label: "Masked token",
                        value: KeychainService.shared.maskedVercelToken() ?? "Unavailable"
                    )

                    if let teamId = appState.preferences.selectedVercelTeamId, !teamId.isEmpty {
                        Divider()
                        SettingsValueRow(label: "Team scope", value: teamId)
                    }
                }

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

                SettingsSection(
                    title: "Actions",
                    subtitle: "Connection actions.",
                    systemImage: "bolt.horizontal"
                ) {
                    SettingsButtonStrip {
                        Button("Disconnect Vercel") {
                            appState.disconnectVercel()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
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

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(
                title: "About",
                subtitle: "App details and credits.",
                systemImage: "heart.text.square"
            ) {
                SettingsTextRow("Made by Anuj Sharma.")
                Divider()
                SettingsTextRow("Build Notifier keeps CircleCI approvals, build status, and Vercel deployments visible in the menu bar.")
            }

            SettingsSection(
                title: "Build",
                subtitle: "Version information.",
                systemImage: "shippingbox"
            ) {
                SettingsValueRow(label: "Version", value: appVersion)
                Divider()
                SettingsValueRow(label: "Platform", value: "macOS 14+")
                Divider()
                SettingsValueRow(label: "Integrations", value: "CircleCI and Vercel")
            }

            SettingsSection(
                title: "Actions",
                subtitle: "Application actions.",
                systemImage: "power"
            ) {
                SettingsButtonStrip {
                    Button("Quit Build Notifier") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.2"
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

private struct SidebarLinkRow: View {
    let title: String
    let destination: URL

    @State private var isHovered = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(destination)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 12, weight: .medium))

                Text(title)
                    .font(.system(size: 12.5, weight: .medium))

                Spacer(minLength: 0)
            }
            .foregroundStyle(isHovered ? AppChrome.accent : AppChrome.textMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: AppChrome.radiusSmall, style: .continuous)
                    .fill(isHovered ? AppChrome.hover : Color.clear)
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
        .help("Open the project on GitHub")
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

private struct SidebarStatusRow: View {
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? .green : AppChrome.separator)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppChrome.text)

            Spacer()

            Text(isActive ? "On" : "Off")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppChrome.textMuted)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(title: String, subtitle: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SettingsRowIcon(systemImage: systemImage)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppChrome.text)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppChrome.textMuted)
                }

                Spacer()
            }
            .padding(.leading, 2)

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

            SettingsRowIcon(systemImage: "arrow.triangle.branch")

            VStack(alignment: .leading, spacing: 3) {
                Text(project.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppChrome.text)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(project.followMode.displayName)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppChrome.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
            .labelsHidden()
            .frame(width: 138)

            Button {
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove project")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct WatchedVercelProjectRow: View {
    let project: WatchedVercelProject
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

            SettingsRowIcon(systemImage: "triangle.fill")

            VStack(alignment: .leading, spacing: 3) {
                Text(project.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppChrome.text)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(project.followMode.displayName)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppChrome.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
            .labelsHidden()
            .frame(width: 138)

            Button {
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove project")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
