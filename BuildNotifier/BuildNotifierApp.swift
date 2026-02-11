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
        .windowResizability(.contentSize)
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
    }
}

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    @Bindable var appState: AppState

    var body: some View {
        Image(systemName: appState.overallStatus.menuBarIcon)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(appState.overallStatus.color)
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
                VStack(spacing: 16) {
                    Text("Setup Required")
                        .font(.headline)
                    
                    Text("Click to configure your CircleCI token")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button("Open Setup") {
                        openWindow(id: "onboarding")
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(width: 280)
                
            case .projectSelection:
                VStack(spacing: 16) {
                    Text("Select Projects")
                        .font(.headline)
                    
                    Text("Click to choose projects to watch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button("Open Project Selector") {
                        openWindow(id: "onboarding")
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(width: 280)
                
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
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                    
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
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 200)
    }
}
