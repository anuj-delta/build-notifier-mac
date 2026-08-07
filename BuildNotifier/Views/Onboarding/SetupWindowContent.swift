import SwiftUI

struct SetupWindowContent: View {
    @Bindable var appState: AppState

    var body: some View {
        Group {
            switch appState.currentScreen {
            case .onboarding:
                OnboardingView(appState: appState)

            case .projectSelection:
                ProjectSelectorView(appState: appState)

            default:
                // Setup finished (or was skipped): close this window instead of showing a
                // redundant "all done" screen - the menu bar takes over from here.
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear { AppWindowManager.closeSetup() }
            }
        }
        .onAppear { AppWindowManager.appWindowAppeared() }
        .onDisappear { AppWindowManager.appWindowDisappeared() }
    }
}
