import XCTest
@testable import BuildNotifier

@MainActor
final class RepoCardTests: XCTestCase {

    // MARK: - Linking

    func testLinkedVercelProjectSharesTheCircleCICard() {
        let appState = makeAppState(
            circleCI: [makeWatchedProject(org: "delta-exchange", repo: "api-console")],
            vercel: [makeWatchedVercelProject(id: "p1", name: "console", repoSlug: "delta-exchange/api-console")]
        )
        appState.buildsByProject["delta-exchange/api-console"] = [makeBuild(branch: "develop")]
        appState.deploymentsByProject["p1"] = [makeDeployment(uid: "d1", branch: "develop")]

        appState.regroupCards()

        XCTAssertEqual(appState.repoCards.count, 1)
        let card = appState.repoCards[0]
        XCTAssertEqual(card.title, "api-console")
        XCTAssertEqual(card.vercel.map(\.id), ["p1"])
        XCTAssertEqual(card.branches.map(\.branch), ["develop"])
        XCTAssertNotNil(card.branches[0].build)
        XCTAssertEqual(card.branches[0].deployments.map(\.id), ["d1"])
    }

    func testRepositoryMatchIsCaseInsensitive() {
        let appState = makeAppState(
            circleCI: [makeWatchedProject(org: "Delta-Exchange", repo: "API-Console")],
            vercel: [makeWatchedVercelProject(id: "p1", name: "console", repoSlug: "delta-exchange/api-console")]
        )
        appState.buildsByProject["Delta-Exchange/API-Console"] = [makeBuild(branch: "develop")]

        appState.regroupCards()

        XCTAssertEqual(appState.repoCards.count, 1)
        XCTAssertEqual(appState.repoCards[0].vercel.map(\.id), ["p1"])
    }

    func testUnlinkedVercelProjectGetsItsOwnCard() {
        let appState = makeAppState(
            circleCI: [makeWatchedProject(org: "delta-exchange", repo: "api-console")],
            vercel: [makeWatchedVercelProject(id: "p1", name: "marketing", repoSlug: nil)]
        )
        appState.buildsByProject["delta-exchange/api-console"] = [makeBuild(branch: "develop")]
        appState.deploymentsByProject["p1"] = [makeDeployment(uid: "d1", branch: "main")]

        appState.regroupCards()

        XCTAssertEqual(Set(appState.repoCards.map(\.title)), ["api-console", "marketing"])
        let vercelCard = appState.repoCards.first { $0.circleCI == nil }
        XCTAssertEqual(vercelCard?.id, "vercel:p1")
        XCTAssertEqual(vercelCard?.branches.map(\.branch), ["main"])
    }

    func testLinkedRepositoryWithNoCircleCIProjectGetsOneCardPerRepository() {
        let appState = makeAppState(
            circleCI: [],
            vercel: [
                makeWatchedVercelProject(id: "p1", name: "web", repoSlug: "delta-exchange/site"),
                makeWatchedVercelProject(id: "p2", name: "docs", repoSlug: "delta-exchange/site")
            ]
        )
        appState.deploymentsByProject["p1"] = [makeDeployment(uid: "d1", branch: "main")]
        appState.deploymentsByProject["p2"] = [makeDeployment(uid: "d2", branch: "main")]

        appState.regroupCards()

        XCTAssertEqual(appState.repoCards.count, 1)
        let card = appState.repoCards[0]
        XCTAssertEqual(card.title, "site")
        XCTAssertEqual(card.vercel.map(\.id), ["p1", "p2"])
        XCTAssertEqual(card.branches[0].deployments.map(\.id), ["d1", "d2"])
    }

    // MARK: - Branches

    func testBranchesAreTheUnionOfBothProviders() {
        let appState = makeAppState(
            circleCI: [makeWatchedProject(org: "delta-exchange", repo: "api-console")],
            vercel: [makeWatchedVercelProject(id: "p1", name: "console", repoSlug: "delta-exchange/api-console")]
        )
        appState.buildsByProject["delta-exchange/api-console"] = [makeBuild(branch: "develop")]
        appState.deploymentsByProject["p1"] = [makeDeployment(uid: "d1", branch: "feature/preview")]

        appState.regroupCards()

        let branches = appState.repoCards[0].branches
        XCTAssertEqual(Set(branches.map(\.branch)), ["develop", "feature/preview"])

        let deploymentOnly = branches.first { $0.branch == "feature/preview" }
        XCTAssertNil(deploymentOnly?.build)
        XCTAssertNil(deploymentOnly?.span)
        XCTAssertEqual(deploymentOnly?.deployments.map(\.id), ["d1"])
    }

    func testBranchesRankByNewestActivityAcrossBothProviders() {
        let appState = makeAppState(
            circleCI: [makeWatchedProject(org: "delta-exchange", repo: "api-console")],
            vercel: [makeWatchedVercelProject(id: "p1", name: "console", repoSlug: "delta-exchange/api-console")]
        )
        appState.buildsByProject["delta-exchange/api-console"] = [
            makeBuild(branch: "develop", startTime: "2026-03-24T10:00:00Z")
        ]
        appState.deploymentsByProject["p1"] = [
            makeDeployment(uid: "d1", branch: "feature/preview", createdAt: 1_774_432_800_000)
        ]

        appState.regroupCards()

        XCTAssertEqual(appState.repoCards[0].branches.map(\.branch), ["feature/preview", "develop"])
    }

    func testDeployedBranchSurvivesTheBranchLimit() {
        let appState = makeAppState(
            circleCI: [makeWatchedProject(org: "delta-exchange", repo: "api-console")],
            vercel: []
        )
        appState.buildsByProject["delta-exchange/api-console"] = (1...8).map { index in
            makeBuild(
                branch: "feature/\(index)",
                buildNum: index,
                startTime: "2026-03-2\(index)T10:00:00Z"
            )
        }
        appState.deployedBranchBySlugByEnv[.sigma] = ["delta-exchange/api-console": "feature/1"]

        appState.regroupCards()

        let branches = appState.repoCards[0].branches.map(\.branch)
        XCTAssertEqual(branches.count, AppState.maxBranchesPerProject + 1)
        XCTAssertTrue(branches.contains("feature/1"))
    }

    func testProductionDeploymentSurvivesTheBranchLimit() {
        let appState = makeAppState(
            circleCI: [],
            vercel: [makeWatchedVercelProject(id: "p1", name: "web", repoSlug: nil)]
        )
        var deployments = (1...8).map { index in
            makeDeployment(
                uid: "preview-\(index)",
                branch: "feature/\(index)",
                createdAt: 1_774_000_000_000 + Int(index) * 60_000
            )
        }
        deployments.append(
            makeDeployment(uid: "prod", branch: "main", createdAt: 1_700_000_000_000, target: "production")
        )
        appState.deploymentsByProject["p1"] = deployments

        appState.regroupCards()

        let branches = appState.repoCards[0].branches.map(\.branch)
        XCTAssertEqual(branches.count, AppState.maxBranchesPerProject + 1)
        XCTAssertEqual(branches.last, "main")
    }

    func testOneDeploymentIsKeptPerProjectAndTarget() {
        let appState = makeAppState(
            circleCI: [],
            vercel: [makeWatchedVercelProject(id: "p1", name: "web", repoSlug: nil)]
        )
        appState.deploymentsByProject["p1"] = [
            makeDeployment(uid: "preview-old", branch: "main", createdAt: 1_700_000_000_000),
            makeDeployment(uid: "preview-new", branch: "main", createdAt: 1_700_000_600_000),
            makeDeployment(uid: "prod", branch: "main", createdAt: 1_700_000_300_000, target: "production")
        ]

        appState.regroupCards()

        let deployments = appState.repoCards[0].branches[0].deployments
        XCTAssertEqual(deployments.map(\.id), ["prod", "preview-new"])
    }

    // MARK: - Card order

    func testCardsRankByNewestActivityAcrossBothProviders() {
        let appState = makeAppState(
            circleCI: [makeWatchedProject(org: "delta-exchange", repo: "api-console")],
            vercel: [makeWatchedVercelProject(id: "p1", name: "marketing", repoSlug: nil)]
        )
        appState.buildsByProject["delta-exchange/api-console"] = [
            makeBuild(branch: "develop", startTime: "2026-03-24T10:00:00Z")
        ]
        appState.deploymentsByProject["p1"] = [
            makeDeployment(uid: "d1", branch: "main", createdAt: 1_774_432_800_000)
        ]

        appState.regroupCards()

        XCTAssertEqual(appState.repoCards.map(\.title), ["marketing", "api-console"])
    }

    func testCardWithNoActivityIsDropped() {
        let appState = makeAppState(
            circleCI: [makeWatchedProject(org: "delta-exchange", repo: "api-console")],
            vercel: [makeWatchedVercelProject(id: "p1", name: "marketing", repoSlug: nil)]
        )

        appState.regroupCards()

        XCTAssertTrue(appState.repoCards.isEmpty)
    }

    // MARK: - Fixtures

    private func makeAppState(
        circleCI: [WatchedProject],
        vercel: [WatchedVercelProject]
    ) -> AppState {
        let appState = AppState()
        appState.preferences.watchedProjects = circleCI
        appState.preferences.watchedVercelProjects = vercel
        return appState
    }

    private func makeWatchedProject(org: String, repo: String) -> WatchedProject {
        WatchedProject(id: "gh/\(org)/\(repo)", vcsType: "gh", orgName: org, repoName: repo)
    }

    private func makeWatchedVercelProject(id: String, name: String, repoSlug: String?) -> WatchedVercelProject {
        WatchedVercelProject(id: id, teamId: nil, projectName: name, teamSlug: "delta", repoSlug: repoSlug)
    }

    private func makeBuild(
        branch: String,
        buildNum: Int = 1,
        startTime: String = "2026-03-24T10:00:00Z"
    ) -> Build {
        Build(
            vcsUrl: "https://github.com/delta-exchange/api-console",
            buildUrl: "https://circleci.com/gh/delta-exchange/api-console/\(buildNum)",
            buildNum: buildNum,
            branch: branch,
            vcsRevision: "rev-\(buildNum)",
            committerName: "Author",
            committerEmail: "author@example.test",
            authorName: "Author",
            authorEmail: "author@example.test",
            subject: "Commit \(buildNum)",
            body: nil,
            why: "github",
            queuedAt: startTime,
            startTime: startTime,
            stopTime: startTime,
            buildTimeMillis: 1000,
            username: "delta-exchange",
            reponame: "api-console",
            lifecycle: "finished",
            outcome: "success",
            status: "success",
            retryOf: nil,
            workflows: WorkflowInfo(
                jobName: "job-\(buildNum)",
                workflowId: "wf-\(buildNum)",
                workflowName: "build-and-deploy"
            ),
            pullRequests: nil
        )
    }

    private func makeDeployment(
        uid: String,
        branch: String,
        createdAt: Int = 1_700_000_000_000,
        target: String = "preview"
    ) -> VercelDeployment {
        VercelDeployment(
            uid: uid,
            name: "web",
            url: "\(uid).vercel.app",
            state: "READY",
            readyState: "READY",
            createdAt: createdAt,
            buildingAt: nil,
            ready: nil,
            meta: VercelDeploymentMeta(
                githubCommitRef: branch,
                githubCommitSha: "abcdef1234567",
                githubCommitMessage: "Deploy \(uid)",
                githubCommitAuthorName: "Author",
                githubCommitAuthorLogin: "author",
                githubPrId: nil,
                gitBranch: nil,
                gitSha: nil
            ),
            creator: nil,
            target: target
        )
    }
}
