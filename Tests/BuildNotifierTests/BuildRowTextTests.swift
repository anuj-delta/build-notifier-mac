import XCTest
@testable import BuildNotifier

final class BuildRowTextTests: XCTestCase {
    func testMergeCommitTitleComesFromTheBody() {
        let build = makeBuild(
            subject: "Merge pull request #281 from Delta-Exchange-Org/develop",
            body: "release: widget contact request dedupe, working rate limits"
        )

        XCTAssertEqual(build.pullRequestTitle, "release: widget contact request dedupe, working rate limits")
    }

    func testMergeCommitBodyKeepsOnlyItsFirstLine() {
        let build = makeBuild(
            subject: "Merge pull request #281 from Delta-Exchange-Org/develop",
            body: "release: faster rails rollout\n\nCuts the rollout from 50 minutes to 11."
        )

        XCTAssertEqual(build.pullRequestTitle, "release: faster rails rollout")
    }

    /// A branch-to-branch merge made in the GitHub UI has an empty body.
    func testMergeCommitWithNoBodyHasNoTitle() {
        let build = makeBuild(
            subject: "Merge pull request #281 from Delta-Exchange-Org/develop",
            body: ""
        )

        XCTAssertNil(build.pullRequestTitle)
    }

    func testSquashMergeTitleComesFromTheSubject() {
        let build = makeBuild(subject: "Keep API tokens out of UserDefaults (#32)")

        XCTAssertEqual(build.pullRequestTitle, "Keep API tokens out of UserDefaults")
    }

    /// The body of an ordinary commit is the long message, not a PR title.
    func testPlainCommitHasNoTitle() {
        let build = makeBuild(
            subject: "fix: exempt signed numbers from csv formula escaping",
            body: "The phone fix only exempted '+' followed by digits, so a negative\nnumber still broke."
        )

        XCTAssertNil(build.pullRequestTitle)
    }

    func testSubjectDropsTheMergeIntoItsOwnBranch() {
        let build = makeBuild(
            subject: "Merge branch 'develop' into feature/DEA-632-csat-category-sentiment-filters",
            branch: "feature/DEA-632-csat-category-sentiment-filters"
        )

        XCTAssertEqual(build.commitSubject, "Merge branch 'develop'")
    }

    func testSubjectKeepsAMergeIntoAnotherBranch() {
        let build = makeBuild(
            subject: "Merge branch 'develop' into feature/DEA-632",
            branch: "main"
        )

        XCTAssertEqual(build.commitSubject, "Merge branch 'develop' into feature/DEA-632")
    }

    func testRowSubjectDropsThePullRequestNumberTheBadgeShows() {
        let build = makeBuild(subject: "Docs: serve an internal docs site (#274)")

        XCTAssertEqual(build.rowSubject, "Docs: serve an internal docs site")
    }

    func testRowSubjectKeepsAPullRequestReferenceMidSentence() {
        let build = makeBuild(subject: "Revert the retry cap (#45) because deploys stalled")

        XCTAssertEqual(build.rowSubject, "Revert the retry cap (#45) because deploys stalled")
    }

    /// A notification has no PR badge beside it, so it keeps the number.
    func testNotificationSubjectKeepsThePullRequestNumber() {
        let build = makeBuild(subject: "Docs: serve an internal docs site (#274)")

        XCTAssertEqual(build.truncatedSubject, "Docs: serve an internal docs site (#274)")
    }

    func testMissingSubjectReadsAsNoCommitMessage() {
        let build = makeBuild(subject: nil)

        XCTAssertEqual(build.commitSubject, "No commit message")
    }

    /// Notifications share the row's subject, so they lose the same noise.
    func testTruncatedSubjectIsAlsoCleaned() {
        let build = makeBuild(
            subject: "Merge branch 'develop' into fix/DEA-588-chat-input-autofocus",
            branch: "fix/DEA-588-chat-input-autofocus"
        )

        XCTAssertEqual(build.truncatedSubject, "Merge branch 'develop'")
    }

    func testYourOwnNameIsHidden() {
        let build = makeBuild(subject: "Ship it", authorName: "Anuj Sharma")

        XCTAssertNil(build.authorDisplayName(excluding: makeUser(name: "Anuj Sharma")))
    }

    func testYourOwnEmailIsHidden() {
        let build = makeBuild(
            subject: "Ship it",
            authorName: "anujs",
            authorEmail: "anuj.sharma@delta.exchange"
        )

        XCTAssertNil(build.authorDisplayName(excluding: makeUser(email: "anuj.sharma@delta.exchange")))
    }

    func testAnotherPersonKeepsTheirName() {
        let build = makeBuild(subject: "Ship it", authorName: "Aditya Jindal")

        XCTAssertEqual(
            build.authorDisplayName(excluding: makeUser(name: "Anuj Sharma")),
            "Aditya Jindal"
        )
    }

    func testWithNoSignedInUserEveryNameShows() {
        let build = makeBuild(subject: "Ship it", authorName: "Anuj Sharma")

        XCTAssertEqual(build.authorDisplayName(excluding: nil), "Anuj Sharma")
    }

    private func makeUser(name: String? = nil, login: String? = nil, email: String? = nil) -> User {
        User(name: name, login: login, avatarUrl: nil, selectedEmail: email)
    }

    private func makeBuild(
        subject: String?,
        body: String? = nil,
        branch: String = "main",
        authorName: String = "Dev",
        authorEmail: String = "dev@example.com"
    ) -> Build {
        Build(
            vcsUrl: "https://github.com/org/repo",
            buildUrl: "https://circleci.com/gh/org/repo/96",
            buildNum: 96,
            branch: branch,
            vcsRevision: "abc123",
            committerName: "GitHub",
            committerEmail: "noreply@github.com",
            authorName: authorName,
            authorEmail: authorEmail,
            subject: subject,
            body: body,
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
            pullRequests: nil
        )
    }
}
