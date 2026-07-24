import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState

    @State private var apiToken = ""
    @State private var isValidating = false
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                AppBrandIcon(size: 64)

                Text("Build Notifier")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Track CircleCI builds and Vercel deployments from your menu bar.")
                    .font(.subheadline)
                    .foregroundStyle(AppChrome.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            Spacer(minLength: 28)

            VStack(alignment: .leading, spacing: 8) {
                Text("CircleCI personal token")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppChrome.textMuted)

                SecureField("Paste your token", text: $apiToken)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .glassCard(cornerRadius: 10)
                    .onSubmit { Task { await validateToken() } }

                HStack(spacing: 14) {
                    Link("Generate a token", destination: IntegrationHelpLinks.circleCITokenPage)
                    Link("Setup guide", destination: IntegrationHelpLinks.circleCIDocs)
                }
                .font(.system(size: 12, weight: .medium))
                .tint(AppChrome.accent)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showError, let error = appState.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppChrome.warning)
                    Text(error)
                        .foregroundStyle(AppChrome.danger)
                        .multilineTextAlignment(.leading)
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppChrome.danger.opacity(0.08))
                .cornerRadius(AppChrome.radiusLarge)
                .padding(.top, 12)
            }

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                Button {
                    Task {
                        await validateToken()
                    }
                } label: {
                    HStack {
                        if isValidating {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        }
                        Text(isValidating ? "Validating…" : "Validate & Continue")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(apiToken.isEmpty || isValidating)

                Button("Skip for now") {
                    appState.currentScreen = .main
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(width: 400, height: 460)
        .background(AppChrome.window)
        .background(MenuWindowConfigurator())
    }

    private func validateToken() async {
        isValidating = true
        showError = false

        let success = await appState.validateToken(apiToken)

        isValidating = false

        if success {
            await appState.loadProjects()
            appState.currentScreen = .projectSelection
        } else {
            showError = true
        }
    }
}
