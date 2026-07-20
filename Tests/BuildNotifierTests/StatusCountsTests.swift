import XCTest
@testable import BuildNotifier

@MainActor
final class StatusCountsTests: XCTestCase {
    func testEmptyStateIsUnknown() {
        let appState = makeAppState()
        XCTAssertEqual(appState.statusCounts.failing, 0)
        XCTAssertEqual(appState.statusCounts.running, 0)
        XCTAssertEqual(appState.statusCounts.passing, 0)
        XCTAssertEqual(appState.overallStatus, .unknown)
    }

    func testCountsSumBranchesAndFailingWinsOverRunning() {
        let appState = makeAppState()
        appState.buildsByProject = [
            "delta-exchange/api-console": [
                makeBuild(buildNum: 10, branch: "main", status: "failed"),
                makeBuild(buildNum: 11, branch: "feature", status: "running")
            ]
        ]

        XCTAssertEqual(appState.statusCounts.failing, 1)
        XCTAssertEqual(appState.statusCounts.running, 1)
        XCTAssertEqual(appState.overallStatus, .failing, "failing must take precedence over running")
    }

    func testLatestBuildPerBranchWins() {
        let appState = makeAppState()
        appState.buildsByProject = [
            "delta-exchange/api-console": [
                makeBuild(buildNum: 20, branch: "main", status: "success"),
                makeBuild(buildNum: 21, branch: "main", status: "failed")
            ]
        ]

        // Only the higher build number (21, failed) counts for the branch.
        XCTAssertEqual(appState.statusCounts.failing, 1)
        XCTAssertEqual(appState.statusCounts.passing, 0)
        XCTAssertEqual(appState.overallStatus, .failing)
    }

    func testAllPassingIsPassing() {
        let appState = makeAppState()
        appState.buildsByProject = [
            "delta-exchange/api-console": [
                makeBuild(buildNum: 30, branch: "main", status: "success"),
                makeBuild(buildNum: 31, branch: "develop", status: "success")
            ]
        ]

        XCTAssertEqual(appState.statusCounts.passing, 2)
        XCTAssertEqual(appState.overallStatus, .passing)
    }

    func testRunningWithoutFailureIsRunning() {
        let appState = makeAppState()
        appState.buildsByProject = [
            "delta-exchange/api-console": [
                makeBuild(buildNum: 40, branch: "main", status: "success"),
                makeBuild(buildNum: 41, branch: "feature", status: "running")
            ]
        ]

        XCTAssertEqual(appState.statusCounts.running, 1)
        XCTAssertEqual(appState.statusCounts.passing, 1)
        XCTAssertEqual(appState.overallStatus, .running)
    }

    func testVercelDeploymentsAreCounted() {
        let appState = makeAppState()
        appState.deploymentsByProject = [
            "web-building": [makeDeployment(uid: "d1", state: "BUILDING")],
            "web-ready": [makeDeployment(uid: "d2", state: "READY")],
            "web-error": [makeDeployment(uid: "d3", state: "ERROR")]
        ]

        XCTAssertEqual(appState.statusCounts.running, 1)
        XCTAssertEqual(appState.statusCounts.passing, 1)
        XCTAssertEqual(appState.statusCounts.failing, 1)
        XCTAssertEqual(appState.overallStatus, .failing, "a failing deploy takes precedence over running/passing")
    }

    func testOnlyFirstDeploymentPerProjectCounts() {
        let appState = makeAppState()
        appState.deploymentsByProject = [
            "web": [
                makeDeployment(uid: "newest", state: "BUILDING"),
                makeDeployment(uid: "older", state: "READY")
            ]
        ]

        // statusCounts tallies `deployments.first` per project, so only the
        // leading BUILDING deployment counts - the trailing READY one is ignored.
        XCTAssertEqual(appState.statusCounts.running, 1)
        XCTAssertEqual(appState.statusCounts.passing, 0)
        XCTAssertEqual(appState.overallStatus, .running)
    }

    func testPendingApprovalTakesPrecedenceOverFailing() {
        let appState = makeAppState()
        appState.buildsByProject = [
            "delta-exchange/api-console": [
                makeBuild(buildNum: 50, branch: "main", status: "failed")
            ]
        ]
        appState.pendingApprovals = [makePendingApproval(workflowId: "wf-approval")]

        // The failing build is still counted...
        XCTAssertEqual(appState.statusCounts.failing, 1)
        // ...but a pending approval outranks every build/deploy state.
        XCTAssertEqual(appState.overallStatus, .pendingApproval)
    }

    // MARK: - Fixtures

    private func makeAppState() -> AppState {
        AppState(poller: BuildPoller(), vercelPoller: VercelPoller(), autoApprovalPoller: AutoApprovalPoller())
    }

    private func makeBuild(buildNum: Int, branch: String, status: String) -> Build {
        Build(
            vcsUrl: "https://github.com/delta-exchange/api-console",
            buildUrl: nil,
            buildNum: buildNum,
            branch: branch,
            vcsRevision: nil,
            committerName: nil,
            committerEmail: nil,
            authorName: nil,
            authorEmail: nil,
            subject: nil,
            body: nil,
            why: nil,
            queuedAt: nil,
            startTime: nil,
            stopTime: nil,
            buildTimeMillis: nil,
            username: "delta-exchange",
            reponame: "api-console",
            lifecycle: nil,
            outcome: status,
            status: status,
            retryOf: nil,
            workflows: WorkflowInfo(jobName: nil, workflowId: "wf-\(buildNum)", workflowName: nil),
            pullRequests: nil
        )
    }

    private func makeDeployment(uid: String, state: String) -> VercelDeployment {
        VercelDeployment(
            uid: uid,
            name: "web",
            url: "\(uid).vercel.app",
            state: state,
            readyState: state,
            createdAt: 1_700_000_000_000,
            buildingAt: nil,
            ready: nil,
            meta: nil,
            creator: nil,
            target: "preview"
        )
    }

    private func makePendingApproval(workflowId: String) -> PendingApproval {
        let job = WorkflowJob(
            id: "job-1",
            name: "hold",
            projectSlug: "delta-exchange/api-console",
            status: "on_hold",
            type: "approval",
            approvedBy: nil,
            startedAt: nil,
            stoppedAt: nil,
            jobNumber: nil
        )
        return PendingApproval(
            workflowId: workflowId,
            job: job,
            build: makeBuild(buildNum: 1, branch: "main", status: "running")
        )
    }
}
