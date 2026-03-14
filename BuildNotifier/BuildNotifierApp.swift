import SwiftUI

@main
struct BuildNotifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    
    var body: some Scene {
        // Menu Bar
        MenuBarExtra {
            MenuBarExtraContent(appState: appState)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)
        
        // Settings Window
        Window("Settings", id: "settings") {
            SettingsView(appState: appState)
        }
        .defaultSize(width: 920, height: 640)
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
        
        // Onboarding Window
        Window("Setup", id: "onboarding") {
            OnboardingWindowContent(appState: appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - App Delegate for hiding dock icon

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - run as menubar-only app
        NSApp.setActivationPolicy(.accessory)
        if let icon = AppBrandAssets.applicationIcon() {
            NSApp.applicationIconImage = icon
        }
    }
}

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    @Bindable var appState: AppState

    var body: some View {
        Group {
            if appState.hasActiveBuildActivity {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 14)
            } else {
                MenuBarIdleGlyph()
                    .frame(width: 16, height: 14)
            }
        }
        .accessibilityLabel(appState.hasActiveBuildActivity ? "Builds running" : "Idle")
    }
}

struct MenuBarIdleGlyph: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Capsule(style: .continuous)
                .fill(Color.primary)
                .frame(width: 12, height: 2.4)

            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.92))
                .frame(width: 9, height: 2.4)

            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.82))
                .frame(width: 11, height: 2.4)
        }
        .frame(width: 14, height: 12, alignment: .center)
    }
}

// MARK: - Menu Bar Extra Content

struct MenuBarExtraContent: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        Group {
            switch appState.currentScreen {
            case .loading:
                LoadingView()
                    .task {
                        await appState.initialize()
                    }
                
            case .onboarding:
                PopoverWelcomeCard(
                    title: "Setup required",
                    subtitle: "Connect CircleCI or skip into Settings to add integrations later.",
                    buttonTitle: "Open Setup",
                    action: {
                        openWindow(id: "onboarding")
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                )
                
            case .projectSelection:
                PopoverWelcomeCard(
                    title: "Choose projects",
                    subtitle: "Pick the CircleCI repositories you want to watch from the menu bar.",
                    buttonTitle: "Open Project Selector",
                    action: {
                        openWindow(id: "onboarding")
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                )
                
            case .main:
                MenuBarContentView(appState: appState)
            }
        }
    }
}

// MARK: - Onboarding Window Content

struct OnboardingWindowContent: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Group {
            switch appState.currentScreen {
            case .onboarding:
                OnboardingView(appState: appState)
                
            case .projectSelection:
                ProjectSelectorView(appState: appState)
                
            default:
                VStack(spacing: 16) {
                    AppBrandIcon(size: 54)
                    
                    Text("Setup Complete!")
                        .font(.headline)
                    
                    Text("You can close this window")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(32)
                .frame(width: 300, height: 200)
            }
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            AppBrandIcon(size: 44)
                .opacity(0.92)

            ProgressView()

            Text("Loading your build status")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 220)
    }
}

struct PopoverWelcomeCard: View {
    let title: String
    let subtitle: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            AppBrandIcon(size: 48)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(buttonTitle) {
                action()
            }
            .buttonStyle(.borderedProminent)

            Divider()
                .padding(.vertical, 2)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 300)
    }
}
