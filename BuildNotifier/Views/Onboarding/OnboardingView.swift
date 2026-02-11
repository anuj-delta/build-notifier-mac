import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState
    
    @State private var apiToken = ""
    @State private var isValidating = false
    @State private var showError = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                
                Text("Build Notifier")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Track CircleCI builds & Vercel deployments")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // Token Input
            VStack(alignment: .leading, spacing: 12) {
                Text("Enter your CircleCI API Token")
                    .font(.headline)
                
                SecureField("Personal API Token", text: $apiToken)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                
                Button {
                    openTokenPage()
                } label: {
                    HStack(spacing: 4) {
                        Text("Get your token from")
                        Text("circleci.com/account/api")
                            .underline()
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            
            // Error Message
            if showError, let error = appState.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .foregroundStyle(.red)
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Validate Button
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
                .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .disabled(apiToken.isEmpty || isValidating)
            
            // Skip option
            Text("or")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button("Skip - Add integrations later in Settings") {
                appState.currentScreen = .main
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.blue)
            
            Spacer()
            
            // Footer
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text("Tokens stored securely in Keychain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 400, height: 480)
    }
    
    private func openTokenPage() {
        if let url = URL(string: "https://circleci.com/account/api") {
            NSWorkspace.shared.open(url)
        }
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
