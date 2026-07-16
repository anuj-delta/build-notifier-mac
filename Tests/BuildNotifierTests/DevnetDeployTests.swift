import XCTest
@testable import BuildNotifier

@MainActor
final class DevnetDeployTests: XCTestCase {
    private let productionBranches = ["main", "master"]

    // MARK: - isDeploy (devnet)

    func testManualDeployOnFeatureBranchIsDevnet() {
        let build = makeBuild(branch: "feat/dea-367", workflowName: "devnet-manual-deploy")
        XCTAssertTrue(DeployEnvironment.devnet.isDeploy(build, productionBranches: productionBranches))
    }

    func testBuildAndDeployOnDevelopIsDevnet() {
        let build = makeBuild(branch: "develop", workflowName: "build-and-deploy")
        XCTAssertTrue(DeployEnvironment.devnet.isDeploy(build, productionBranches: productionBranches))
    }

    func testBuildAndDeployOnMainIsNotDevnet() {
        let build = makeBuild(branch: "main", workflowName: "build-and-deploy")
        XCTAssertFalse(DeployEnvironment.devnet.isDeploy(build, productionBranches: productionBranches))
    }

    func testManualDeployOnMainStillCountsAsDevnet() {
        let build = makeBuild(branch: "main", workflowName: "devnet-manual-deploy")
        XCTAssertTrue(DeployEnvironment.devnet.isDeploy(build, productionBranches: productionBranches))
    }

    func testUnrelatedWorkflowIsNotDevnet() {
        let build = makeBuild(branch: "develop", workflowName: "ci")
        XCTAssertFalse(DeployEnvironment.devnet.isDeploy(build, productionBranches: productionBranches))
    }

    func testMissingWorkflowNameIsNotDevnet() {
        let build = makeBuild(branch: "develop", workflowName: nil)
        XCTAssertFalse(DeployEnvironment.devnet.isDeploy(build, productionBranches: productionBranches))
    }

    func testWorkflowMatchIsCaseInsensitive() {
        let build = makeBuild(branch: "develop", workflowName: "Build-And-Deploy")
        XCTAssertTrue(DeployEnvironment.devnet.isDeploy(build, productionBranches: productionBranches))
    }

    // MARK: - isDeploy (sigma)

    func testSigmaManualDeployIsSigma() {
        let build = makeBuild(branch: "INFRA-782/sigma-chatbot", workflowName: "sigma-manual-deploy")
        XCTAssertTrue(DeployEnvironment.sigma.isDeploy(build, productionBranches: productionBranches))
    }

    func testSigmaManualDeployOnMainStillCountsAsSigma() {
        let build = makeBuild(branch: "main", workflowName: "sigma-manual-deploy")
        XCTAssertTrue(DeployEnvironment.sigma.isDeploy(build, productionBranches: productionBranches))
    }

    func testDevnetAndSigmaWorkflowsDoNotCrossMatch() {
        let devnetBuild = makeBuild(branch: "develop", workflowName: "build-and-deploy")
        let sigmaBuild = makeBuild(branch: "feat/x", workflowName: "sigma-manual-deploy")
        XCTAssertFalse(DeployEnvironment.sigma.isDeploy(devnetBuild, productionBranches: productionBranches))
        XCTAssertFalse(DeployEnvironment.devnet.isDeploy(sigmaBuild, productionBranches: productionBranches))
    }

    // MARK: - deployWorkflowsNewestFirst

    func testCandidatesAreOrderedNewestFirst() {
        let candidates = DeployEnvironment.devnet.deployWorkflowsNewestFirst(
            builds: [
                makeBuild(branch: "develop", workflowName: "build-and-deploy", workflowId: "wf-old", startTime: "2026-07-13T09:00:00Z"),
                makeBuild(branch: "feat/dea-367", workflowName: "devnet-manual-deploy", workflowId: "wf-new", startTime: "2026-07-13T10:00:00Z")
            ],
            productionBranches: productionBranches
        )
        XCTAssertEqual(candidates.map(\.workflowId), ["wf-new", "wf-old"])
        XCTAssertEqual(candidates.first?.branch, "feat/dea-367")
    }

    func testCandidatesCollapseJobsOfTheSameWorkflow() {
        // v1.1 returns one build per job; a workflow must appear once.
        let candidates = DeployEnvironment.devnet.deployWorkflowsNewestFirst(
            builds: [
                makeBuild(branch: "develop", workflowName: "build-and-deploy", status: "success", workflowId: "wf-dep", startTime: "2026-07-13T10:00:00Z"),
                makeBuild(branch: "develop", workflowName: "build-and-deploy", status: "canceled", workflowId: "wf-dep", startTime: "2026-07-13T10:05:00Z")
            ],
            productionBranches: productionBranches
        )
        XCTAssertEqual(candidates.map(\.workflowId), ["wf-dep"])
    }

    func testCandidatesExcludeProductionAndNonDeployWorkflows() {
        let candidates = DeployEnvironment.devnet.deployWorkflowsNewestFirst(
            builds: [
                makeBuild(branch: "main", workflowName: "build-and-deploy", workflowId: "wf-prod"),
                makeBuild(branch: "develop", workflowName: "ci", workflowId: "wf-ci"),
                makeBuild(branch: "develop", workflowName: "build-and-deploy", workflowId: "wf-devnet")
            ],
            productionBranches: productionBranches
        )
        XCTAssertEqual(candidates.map(\.workflowId), ["wf-devnet"])
    }

    func testSigmaCandidatesOnlyMatchSigmaWorkflow() {
        let candidates = DeployEnvironment.sigma.deployWorkflowsNewestFirst(
            builds: [
                makeBuild(branch: "develop", workflowName: "build-and-deploy", workflowId: "wf-devnet"),
                makeBuild(branch: "feat/x", workflowName: "sigma-manual-deploy", workflowId: "wf-sigma")
            ],
            productionBranches: productionBranches
        )
        XCTAssertEqual(candidates.map(\.workflowId), ["wf-sigma"])
    }

    // MARK: - markBranchDeployed baseline

    func testRedeployBaselinesExistingSuccessfulWorkflows() {
        let appState = makeAppState(builds: [
            makeBuild(buildNum: 11, branch: "feat/dea-367", workflowName: "devnet-manual-deploy")
        ])
        appState.markBranchDeployed(projectSlug: slug, branch: "feat/dea-367")

        XCTAssertTrue(appState.deployedBranchKeys.contains(AppState.deployKey(projectSlug: slug, branch: "feat/dea-367")))
        // The already-completed wf-11 must be treated as handled so it can't
        // instantly re-celebrate on the next poll.
        XCTAssertTrue(appState.celebratedSuccessWorkflows.contains("wf-11"))
    }

    func testRedeployDoesNotBaselineOtherBranches() {
        let appState = makeAppState(builds: [
            makeBuild(buildNum: 10, branch: "develop", workflowName: "build-and-deploy"),
            makeBuild(buildNum: 11, branch: "feat/dea-367", workflowName: "devnet-manual-deploy")
        ])
        appState.markBranchDeployed(projectSlug: slug, branch: "feat/dea-367")

        XCTAssertTrue(appState.celebratedSuccessWorkflows.contains("wf-11"))
        XCTAssertFalse(appState.celebratedSuccessWorkflows.contains("wf-10"))
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
        workflowId: String? = nil,
        startTime: String = "2026-07-13T10:00:00Z"
    ) -> Build {
        Build(
            vcsUrl: "https://github.com/delta-exchange/support-chatbot",
            buildUrl: "https://circleci.com/gh/delta-exchange/support-chatbot/\(buildNum)",
            buildNum: buildNum,
            branch: branch,
            vcsRevision: "rev-\(buildNum)",
            committerName: "Test Author",
            committerEmail: "author@example.test",
            authorName: "Test Author",
            authorEmail: "author@example.test",
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
            workflows: WorkflowInfo(jobName: "job", workflowId: workflowId ?? "wf-\(buildNum)", workflowName: workflowName),
            pullRequests: nil
        )
    }
}
