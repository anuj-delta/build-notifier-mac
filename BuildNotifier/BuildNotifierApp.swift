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
        .defaultSize(width: 860, height: 580)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
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
            if !appState.pendingApprovals.isEmpty {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 16, height: 14)
            } else if appState.hasActiveBuildActivity {
                MenuBarSpinnerGlyph()
            } else {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 16, height: 14)
            }
        }
        .accessibilityLabel(menuBarAccessibilityLabel)
    }

    private var menuBarAccessibilityLabel: String {
        if !appState.pendingApprovals.isEmpty {
            return "Approval pending"
        }
        return appState.hasActiveBuildActivity ? "Builds running" : "Idle"
    }
}

struct MenuBarSpinnerGlyph: View {
    @State private var isAnimating = false

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .symbolRenderingMode(.monochrome)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .frame(width: 16, height: 14)
            .onAppear {
                if !isAnimating {
                    isAnimating = true
                }
            }
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: isAnimating)
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
                        AppWindowManager.dismissActiveMenuBarWindow {
                            openWindow(id: "onboarding")
                            NSApplication.shared.activate(ignoringOtherApps: true)
                        }
                    }
                )
                
            case .projectSelection:
                PopoverWelcomeCard(
                    title: "Choose projects",
                    subtitle: "Pick the CircleCI repositories you want to watch from the menu bar.",
                    buttonTitle: "Open Project Selector",
                    action: {
                        AppWindowManager.dismissActiveMenuBarWindow {
                            openWindow(id: "onboarding")
                            NSApplication.shared.activate(ignoringOtherApps: true)
                        }
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
