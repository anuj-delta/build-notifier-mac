import XCTest
@testable import BuildNotifier

@MainActor
final class DevnetDeployTests: XCTestCase {
    private let productionBranches = ["main", "master"]

    // MARK: - isDevnetDeploy

    func testManualDeployOnFeatureBranchIsDevnet() {
        let build = makeBuild(branch: "feat/dea-367", workflowName: "devnet-manual-deploy")
        XCTAssertTrue(AppState.isDevnetDeploy(build, productionBranches: productionBranches))
    }

    func testBuildAndDeployOnDevelopIsDevnet() {
        let build = makeBuild(branch: "develop", workflowName: "build-and-deploy")
        XCTAssertTrue(AppState.isDevnetDeploy(build, productionBranches: productionBranches))
    }

    func testBuildAndDeployOnMainIsNotDevnet() {
        let build = makeBuild(branch: "main", workflowName: "build-and-deploy")
        XCTAssertFalse(AppState.isDevnetDeploy(build, productionBranches: productionBranches))
    }

    func testManualDeployOnMainStillCountsAsDevnet() {
        let build = makeBuild(branch: "main", workflowName: "devnet-manual-deploy")
        XCTAssertTrue(AppState.isDevnetDeploy(build, productionBranches: productionBranches))
    }

    func testUnrelatedWorkflowIsNotDevnet() {
        let build = makeBuild(branch: "develop", workflowName: "ci")
        XCTAssertFalse(AppState.isDevnetDeploy(build, productionBranches: productionBranches))
    }

    func testMissingWorkflowNameIsNotDevnet() {
        let build = makeBuild(branch: "develop", workflowName: nil)
        XCTAssertFalse(AppState.isDevnetDeploy(build, productionBranches: productionBranches))
    }

    func testWorkflowMatchIsCaseInsensitive() {
        let build = makeBuild(branch: "develop", workflowName: "Build-And-Deploy")
        XCTAssertTrue(AppState.isDevnetDeploy(build, productionBranches: productionBranches))
    }

    // MARK: - devnetDeployedBranch

    func testDeployedBranchIsLatestSuccessfulDeploy() {
        let appState = makeAppState(builds: [
            makeBuild(buildNum: 10, branch: "develop", workflowName: "build-and-deploy", startTime: "2026-07-13T09:00:00Z"),
            makeBuild(buildNum: 11, branch: "feat/dea-367", workflowName: "devnet-manual-deploy", startTime: "2026-07-13T10:00:00Z")
        ])
        XCTAssertEqual(appState.devnetDeployedBranch(forSlug: slug), "feat/dea-367")
    }

    func testRunningDeployDoesNotOverrideLastSuccess() {
        let appState = makeAppState(builds: [
            makeBuild(buildNum: 10, branch: "develop", workflowName: "build-and-deploy", status: "success", startTime: "2026-07-13T09:00:00Z"),
            makeBuild(buildNum: 11, branch: "feat/dea-367", workflowName: "devnet-manual-deploy", status: "running", startTime: "2026-07-13T10:00:00Z")
        ])
        XCTAssertEqual(appState.devnetDeployedBranch(forSlug: slug), "develop")
    }

    func testMainDeployIsNotReportedAsDevnet() {
        let appState = makeAppState(builds: [
            makeBuild(buildNum: 10, branch: "main", workflowName: "build-and-deploy", startTime: "2026-07-13T10:00:00Z")
        ])
        XCTAssertNil(appState.devnetDeployedBranch(forSlug: slug))
    }

    func testNoDevnetDeployReturnsNil() {
        let appState = makeAppState(builds: [
            makeBuild(buildNum: 10, branch: "develop", workflowName: "ci", startTime: "2026-07-13T10:00:00Z")
        ])
        XCTAssertNil(appState.devnetDeployedBranch(forSlug: slug))
    }

    // MARK: - Helpers

    private let slug = "delta-exchange/support-chatbot"

    private func makeAppState(builds: [Build]) -> AppState {
        let appState = AppState(poller: BuildPoller(), vercelPoller: VercelPoller(), autoApprovalPoller: AutoApprovalPoller())
        appState.preferences.productionBranches = productionBranches
        appState.buildsByProject = [slug: builds]
        return appState
    }

    private func makeBuild(
        buildNum: Int = 1,
        branch: String,
        workflowName: String?,
        status: String = "success",
        startTime: String = "2026-07-13T10:00:00Z"
    ) -> Build {
        Build(
            vcsUrl: "https://github.com/delta-exchange/support-chatbot",
            buildUrl: "https://circleci.com/gh/delta-exchange/support-chatbot/\(buildNum)",
            buildNum: buildNum,
            branch: branch,
            vcsRevision: "rev-\(buildNum)",
            committerName: "Anuj Sharma",
            committerEmail: "anuj.sharma@delta.exchange",
            authorName: "Anuj Sharma",
            authorEmail: "anuj.sharma@delta.exchange",
            subject: "Commit \(buildNum)",
            body: nil,
            why: "github",
            queuedAt: startTime,
            startTime: startTime,
            stopTime: nil,
            buildTimeMillis: nil,
            username: "delta-exchange",
            reponame: "support-chatbot",
            lifecycle: status == "success" ? "finished" : "running",
            outcome: status == "success" ? "success" : nil,
            status: status,
            retryOf: nil,
            workflows: WorkflowInfo(jobName: "job", workflowId: "wf-\(buildNum)", workflowName: workflowName),
            pullRequests: nil
        )
    }
}
