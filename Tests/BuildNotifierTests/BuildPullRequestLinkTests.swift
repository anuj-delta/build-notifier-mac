import XCTest
@testable import BuildNotifier

final class BuildPullRequestLinkTests: XCTestCase {
    func testOpenPullRequestWins() {
        let build = makeBuild(
            subject: "Merge pull request #281 from Delta-Exchange-Org/develop",
            pullRequests: [PullRequest(headSha: "abc123", url: "https://github.com/org/repo/pull/300")]
        )

        XCTAssertEqual(build.pullRequestUrl, "https://github.com/org/repo/pull/300")
        XCTAssertEqual(build.pullRequestNumber, 300)
    }

    func testMergeCommitSubjectLinksToTheMergedPullRequest() {
        let build = makeBuild(subject: "Merge pull request #281 from Delta-Exchange-Org/develop")

        XCTAssertEqual(build.pullRequestUrl, "https://github.com/org/repo/pull/281")
        XCTAssertEqual(build.pullRequestNumber, 281)
    }

    func testSquashMergeSubjectLinksToTheMergedPullRequest() {
        let build = makeBuild(subject: "Keep API tokens out of UserDefaults (#32)")

        XCTAssertEqual(build.pullRequestNumber, 32)
    }

    func testPullRequestReferenceMidSubjectIsIgnored() {
        let build = makeBuild(subject: "Revert the retry cap (#45) because deploys stalled")

        XCTAssertNil(build.pullRequestNumber)
    }

    func testBranchMergeSubjectHasNoPullRequest() {
        let build = makeBuild(subject: "Merge branch 'develop' into feature/DEA-632")

        XCTAssertNil(build.pullRequestUrl)
        XCTAssertNil(build.pullRequestNumber)
    }

    func testBitbucketMergeSubjectHasNoPullRequest() {
        let build = makeBuild(
            subject: "Merge pull request #281 from Delta-Exchange-Org/develop",
            vcsUrl: "https://bitbucket.org/org/repo"
        )

        XCTAssertNil(build.pullRequestUrl)
    }

    private func makeBuild(
        subject: String?,
        vcsUrl: String = "https://github.com/org/repo",
        pullRequests: [PullRequest]? = nil
    ) -> Build {
        Build(
            vcsUrl: vcsUrl,
            buildUrl: "https://circleci.com/gh/org/repo/96",
            buildNum: 96,
            branch: "main",
            vcsRevision: "abc123",
            committerName: "Dev",
            committerEmail: "dev@example.com",
            authorName: "Dev",
            authorEmail: "dev@example.com",
            subject: subject,
            body: nil,
            why: "github",
            queuedAt: nil,
            startTime: nil,
            stopTime: nil,
            buildTimeMillis: nil,
            username: "org",
            reponame: "repo",
            lifecycle: "running",
            outcome: nil,
            status: "running",
            retryOf: nil,
            workflows: nil,
            pullRequests: pullRequests
        )
    }
}
