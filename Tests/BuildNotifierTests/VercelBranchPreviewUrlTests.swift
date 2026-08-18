import XCTest
@testable import BuildNotifier

final class VercelBranchPreviewUrlTests: XCTestCase {
    func testBranchPreviewUrlUsesTheAliasVercelReports() {
        let deployment = makeDeployment(
            branchAlias: "web-app-india-preview-git-chore-india-ci-delta-exchange.vercel.app"
        )

        XCTAssertEqual(
            deployment.branchPreviewUrl,
            "https://web-app-india-preview-git-chore-india-ci-delta-exchange.vercel.app"
        )
    }

    /// Vercel truncates a long branch host and appends its own hash, so the alias is the only
    /// source for it.
    func testBranchPreviewUrlKeepsTheTruncatedAlias() {
        let deployment = makeDeployment(
            branchAlias: "landing-india-previews-git-fix-dea-703-co-58dbc9-delta-exchange.vercel.app"
        )

        XCTAssertEqual(
            deployment.branchPreviewUrl,
            "https://landing-india-previews-git-fix-dea-703-co-58dbc9-delta-exchange.vercel.app"
        )
    }

    func testBranchPreviewUrlIsNilForProductionDeployment() {
        let deployment = makeDeployment(
            branchAlias: "web-app-india-preview-git-master-delta-exchange.vercel.app",
            target: "production"
        )

        XCTAssertNil(deployment.branchPreviewUrl)
    }

    func testBranchPreviewUrlIsNilWithoutAnAlias() {
        XCTAssertNil(makeDeployment(branchAlias: nil).branchPreviewUrl)
        XCTAssertNil(makeDeployment(branchAlias: "").branchPreviewUrl)
    }

    func testDeploymentDecodesTheBranchAliasFromMeta() throws {
        let json = """
        {"uid":"dpl_1","name":"web","createdAt":1700000000000,
         "meta":{"branchAlias":"web-git-main-delta.vercel.app"}}
        """

        let deployment = try JSONDecoder().decode(VercelDeployment.self, from: Data(json.utf8))

        XCTAssertEqual(deployment.branchPreviewUrl, "https://web-git-main-delta.vercel.app")
    }

    private func makeDeployment(branchAlias: String?, target: String? = "preview") -> VercelDeployment {
        VercelDeployment(
            uid: "dpl_1",
            name: "web-app-india-preview",
            url: "web-app-india-preview-9k2xq1hf-delta.vercel.app",
            state: "READY",
            readyState: "READY",
            createdAt: 1_700_000_000_000,
            buildingAt: nil,
            ready: nil,
            meta: VercelDeploymentMeta(
                githubCommitRef: "chore/india-ci",
                githubCommitSha: "4f1c9abcdef",
                githubCommitMessage: "chore(env): point india ci preview at sigma",
                githubCommitAuthorName: "Anuj Sharma",
                githubCommitAuthorLogin: "anuj-delta",
                githubPrId: "10678",
                gitBranch: nil,
                gitSha: nil,
                branchAlias: branchAlias
            ),
            creator: nil,
            target: target
        )
    }
}
