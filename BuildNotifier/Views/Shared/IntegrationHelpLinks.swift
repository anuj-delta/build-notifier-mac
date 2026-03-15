import SwiftUI

enum IntegrationHelpLinks {
    static let circleCITokenPage = URL(string: "https://app.circleci.com/settings/user/tokens")!
    static let circleCIDocs = URL(string: "https://circleci.com/docs/guides/permissions-authentication/personal-api-tokens/")!
    static let vercelTokenPage = URL(string: "https://vercel.com/account/settings/tokens")!
    static let vercelDocs = URL(string: "https://vercel.com/guides/how-do-i-use-a-vercel-api-access-token")!
}

struct IntegrationHelpLinkRow: View {
    let title: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.blue)

                Text(title)
                    .font(.subheadline)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
