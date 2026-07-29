import XCTest
@testable import BuildNotifier

final class VercelBranchPreviewUrlTests: XCTestCase {
    func testBranchPreviewUrlUsesProjectBranchAndScope() {
        let deployment = makeDeployment(branch: "chore/india-ci")

        XCTAssertEqual(
            deployment.branchPreviewUrl(scopeSlug: "delta"),
            "https://web-app-india-preview-git-chore-india-ci-delta.vercel.app"
        )
    }

    func testBranchPreviewUrlSlugifiesBranchAndScope() {
        let deployment = makeDeployment(branch: "Feature/ENV_Fix (2)")

        XCTAssertEqual(
            deployment.branchPreviewUrl(scopeSlug: "Delta Exchange"),
            "https://web-app-india-preview-git-feature-env-fix-2-delta-exchange.vercel.app"
        )
    }

    func testBranchPreviewUrlIsNilForProductionDeployment() {
        let deployment = makeDeployment(branch: "master", target: "production")

        XCTAssertNil(deployment.branchPreviewUrl(scopeSlug: "delta"))
    }

    func testBranchPreviewUrlIsNilWithoutScopeOrBranch() {
        XCTAssertNil(makeDeployment(branch: "main").branchPreviewUrl(scopeSlug: nil))
        XCTAssertNil(makeDeployment(branch: "main").branchPreviewUrl(scopeSlug: "  "))
        XCTAssertNil(makeDeployment(branch: nil).branchPreviewUrl(scopeSlug: "delta"))
    }

    /// Vercel truncates and hashes hosts longer than this, so a derived URL would 404.
    func testBranchPreviewUrlIsNilWhenHostExceedsSixtyThreeCharacters() {
        // "web-app-india-preview" + "-git-" + branch + "-" + "delta" = 32 + branch length.
        let deployment = makeDeployment(branch: String(repeating: "a", count: 32))

        XCTAssertNil(deployment.branchPreviewUrl(scopeSlug: "delta"))
        XCTAssertNotNil(makeDeployment(branch: String(repeating: "a", count: 31)).branchPreviewUrl(scopeSlug: "delta"))
    }

    func testUrlSlugTrimsSeparators() {
        XCTAssertEqual(VercelDeployment.urlSlug("--chore/env--"), "chore-env")
        XCTAssertEqual(VercelDeployment.urlSlug("release/v1.9.0"), "release-v1-9-0")
        XCTAssertNil(VercelDeployment.urlSlug("///"))
    }

    func testWatchedProjectDecodesWithoutStoredTeamSlug() throws {
        let json = #"{"id":"prj_1","teamId":"team_1","projectName":"web"}"#

        let project = try JSONDecoder().decode(WatchedVercelProject.self, from: Data(json.utf8))

        XCTAssertNil(project.teamSlug)
        XCTAssertEqual(project.projectName, "web")
    }

    private func makeDeployment(branch: String?, target: String? = "preview") -> VercelDeployment {
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
                githubCommitRef: branch,
                githubCommitSha: "4f1c9abcdef",
                githubCommitMessage: "chore(env): point india ci preview at sigma",
                githubCommitAuthorName: "Anuj Sharma",
                githubCommitAuthorLogin: "anuj-delta",
                githubPrId: "10678",
                gitBranch: nil,
                gitSha: nil
            ),
            creator: nil,
            target: target
        )
    }
}
