import SwiftUI

struct RepositoryPathLabel: View {
    let organization: String?
    let repository: String
    let repositoryFont: Font
    let organizationFont: Font
    let repositoryColor: Color
    let organizationColor: Color
    let truncationMode: Text.TruncationMode

    var body: some View {
        labelText
            .lineLimit(1)
            .truncationMode(truncationMode)
    }

    private var labelText: Text {
        guard let organization, !organization.isEmpty else {
            return Text(repository)
                .font(repositoryFont)
                .foregroundStyle(repositoryColor)
        }

        return Text("\(organization)/")
            .font(organizationFont)
            .foregroundStyle(organizationColor)
        + Text(repository)
            .font(repositoryFont)
            .foregroundStyle(repositoryColor)
    }
}
