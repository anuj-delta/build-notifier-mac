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
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppChrome.accent)
                    .frame(width: 16, height: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppChrome.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(destination.host() ?? destination.absoluteString)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppChrome.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppChrome.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
