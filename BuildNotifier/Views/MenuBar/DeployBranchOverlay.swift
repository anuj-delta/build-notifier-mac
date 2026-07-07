import SwiftUI

struct DeployBranchOverlay: View {
    let project: WatchedProject
    let appState: AppState
    let onDismiss: () -> Void

    private enum Field {
        case branch
        case env
    }

    @State private var branch = ""
    @State private var env = "devnet"
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @FocusState private var focusedField: Field?

    private var canDeploy: Bool {
        !branch.trimmingCharacters(in: .whitespaces).isEmpty && !isSubmitting
    }

    var body: some View {
        ZStack {
            ModalScrim(isDismissable: !isSubmitting, onDismiss: onDismiss)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppChrome.accent)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(AppChrome.accent.opacity(0.14)))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Deploy a Branch")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppChrome.text)

                        Text("\(project.orgName)/\(project.repoName)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppChrome.textMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    field(label: "Branch", field: .branch) {
                        TextField("feature/my-branch", text: $branch)
                            .focused($focusedField, equals: .branch)
                            .onSubmit { if canDeploy { deploy() } }
                    }

                    field(label: "Environment", field: .env, hint: "pipeline parameter · env") {
                        TextField("devnet", text: $env)
                            .focused($focusedField, equals: .env)
                    }
                }

                if let message = errorMessage ?? successMessage {
                    statusBanner(message: message, isError: errorMessage != nil)
                }

                HStack(spacing: 10) {
                    Button("Cancel") { onDismiss() }
                        .buttonStyle(ModalActionButtonStyle(kind: .secondary))
                        .disabled(isSubmitting)

                    Button {
                        deploy()
                    } label: {
                        HStack(spacing: 6) {
                            if isSubmitting {
                                ProgressView().controlSize(.small)
                            }
                            Text(isSubmitting ? "Deploying" : "Deploy")
                        }
                    }
                    .buttonStyle(ModalActionButtonStyle(kind: .primary))
                    .disabled(!canDeploy)
                }
            }
            .padding(20)
            .modalSurface(width: 324)
        }
        .onAppear { focusedField = .branch }
    }

    @ViewBuilder
    private func field(
        label: String,
        field: Field,
        hint: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppChrome.radiusSmall, style: .continuous)
        let isFocused = focusedField == field

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppChrome.text)
                if let hint {
                    Text(hint)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(AppChrome.textMuted)
                }
            }

            content()
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(AppChrome.text)
                .disabled(isSubmitting)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(shape.fill(AppChrome.glassPanel))
                .overlay(shape.strokeBorder(isFocused ? AppChrome.accent.opacity(0.9) : AppChrome.glassStroke, lineWidth: 1))
                .animation(.easeOut(duration: 0.12), value: isFocused)
        }
    }

    @ViewBuilder
    private func statusBanner(message: String, isError: Bool) -> some View {
        let tint = isError ? AppChrome.danger : AppChrome.accent
        HStack(spacing: 7) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: AppChrome.radiusSmall, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    private func deploy() {
        guard canDeploy else { return }
        let branchName = branch.trimmingCharacters(in: .whitespaces)
        let envName = env.trimmingCharacters(in: .whitespaces)
        focusedField = nil
        isSubmitting = true
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                let pipeline = try await appState.triggerDeployment(
                    project: project,
                    branch: branchName,
                    env: envName
                )
                successMessage = "Triggered pipeline #\(pipeline.number)"
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                onDismiss()
            } catch {
                isSubmitting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
