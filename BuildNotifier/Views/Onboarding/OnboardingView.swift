import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState

    @State private var apiToken = ""
    @State private var isValidating = false
    @State private var showError = false

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                AppBrandIcon(size: 70)

                Text("Build Notifier")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Track CircleCI builds and Vercel deployments from one quiet menu bar app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            HStack(spacing: 10) {
                onboardingFact("Menu bar only", systemImage: "menubar.rectangle")
                onboardingFact("Native alerts", systemImage: "bell.badge")
                onboardingFact("Private local storage", systemImage: "lock.shield")
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("Connect CircleCI")
                    .font(.headline)

                Text("Add your CircleCI personal token to fetch builds, approvals, and project lists.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                SecureField("Personal API Token", text: $apiToken)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 8) {
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
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(14)

            if showError, let error = appState.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.08))
                .cornerRadius(10)
            }

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
                        Text(isValidating ? "Validating..." : "Validate & Continue")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(apiToken.isEmpty || isValidating)

                Button("Skip for now and configure integrations later") {
                    appState.currentScreen = .main
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(32)
        .frame(width: 430, height: 520)
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

    private func onboardingFact(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(999)
    }
}
