import SwiftUI
import AppKit

/// What the menu bar panel shows, by app screen.
struct MenuBarRoot: View {
    @Bindable var appState: AppState

    var body: some View {
        Group {
            switch appState.currentScreen {
            case .loading:
                LoadingView()

            case .onboarding:
                PopoverWelcomeCard(
                    title: "Setup required",
                    subtitle: "Connect CircleCI or skip into Settings to add integrations later.",
                    buttonTitle: "Open Setup",
                    action: { openSetup() }
                )

            case .projectSelection:
                PopoverWelcomeCard(
                    title: "Choose projects",
                    subtitle: "Pick the CircleCI repositories you want to watch from the menu bar.",
                    buttonTitle: "Open Project Selector",
                    action: { openSetup() }
                )

            case .main:
                MenuBarContentView(appState: appState)
            }
        }
    }

    private func openSetup() {
        AppWindowManager.dismissActiveMenuBarWindow {
            AppWindowManager.openSetup(appState)
        }
    }
}

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
