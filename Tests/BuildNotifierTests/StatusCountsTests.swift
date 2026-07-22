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

    func testCountsSumBranchesAndRunningWinsOverFailing() {
        let appState = makeAppState()
        appState.buildsByProject = [
            "delta-exchange/api-console": [
                makeBuild(buildNum: 10, branch: "main", status: "failed"),
                makeBuild(buildNum: 11, branch: "feature", status: "running")
            ]
        ]

        XCTAssertEqual(appState.statusCounts.failing, 1)
        XCTAssertEqual(appState.statusCounts.running, 1)
        XCTAssertEqual(appState.overallStatus, .running, "an active build must outrank a failure")
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
        XCTAssertEqual(appState.overallStatus, .running, "a running deploy outranks a failing one")
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

    func testStaleFeatureFailureExcludedButKeyBranchAlwaysCounts() {
        let appState = makeAppState()
        appState.buildsByProject = [
            "delta-exchange/api-console": [
                // Abandoned feature branch that failed a month ago: must not count.
                makeBuild(buildNum: 10, branch: "old-feature", status: "failed", startTime: stale),
                // main failed just as long ago, but a key branch always counts.
                makeBuild(buildNum: 11, branch: "main", status: "failed", startTime: stale)
            ]
        ]

        XCTAssertEqual(appState.statusCounts.failing, 1, "only the key branch's failure counts")
        XCTAssertEqual(appState.overallStatus, .failing)
    }

    func testRecentFeatureBranchCounts() {
        let appState = makeAppState()
        appState.buildsByProject = [
            "delta-exchange/api-console": [
                makeBuild(buildNum: 20, branch: "feature", status: "running", startTime: recent)
            ]
        ]

        XCTAssertEqual(appState.statusCounts.running, 1)
        XCTAssertEqual(appState.overallStatus, .running)
    }

    func testFailureBeyondVisibleBranchLimitIsExcluded() {
        let appState = makeAppState()
        // Six recent non-key branches; only the five most-recent are visible, so
        // the sixth (oldest, failed) drops out of the count even though it's fresh.
        var builds = (0..<5).map { i in
            makeBuild(buildNum: 100 + i, branch: "feat-\(i)", status: "success",
                      startTime: iso(Date(timeIntervalSinceNow: -Double(i) * 60)))
        }
        builds.append(
            makeBuild(buildNum: 200, branch: "feat-old", status: "failed",
                      startTime: iso(Date(timeIntervalSinceNow: -3600)))
        )
        appState.buildsByProject = ["delta-exchange/api-console": builds]

        XCTAssertEqual(appState.statusCounts.passing, 5)
        XCTAssertEqual(appState.statusCounts.failing, 0, "the crowded-out sixth branch must not count")
        XCTAssertEqual(appState.overallStatus, .passing)
    }

    func testStalePreviewDeployExcludedButProductionAlwaysCounts() {
        let appState = makeAppState()
        appState.deploymentsByProject = [
            "preview-stale": [makeDeployment(uid: "p1", state: "ERROR", target: "preview", createdAt: 1_600_000_000_000)],
            "prod": [makeDeployment(uid: "p2", state: "ERROR", target: "production", createdAt: 1_600_000_000_000)]
        ]

        XCTAssertEqual(appState.statusCounts.failing, 1, "only the production deploy's failure counts")
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

    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    /// A month ago - safely outside the 7-day recency window.
    private var stale: String { iso(Date(timeIntervalSinceNow: -30 * 24 * 60 * 60)) }
    /// An hour ago - safely inside the recency window.
    private var recent: String { iso(Date(timeIntervalSinceNow: -60 * 60)) }

    private func makeAppState() -> AppState {
        AppState(poller: BuildPoller(), vercelPoller: VercelPoller(), autoApprovalPoller: AutoApprovalPoller())
    }

    private func makeBuild(buildNum: Int, branch: String, status: String, startTime: String? = nil) -> Build {
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
            startTime: startTime,
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

    private func makeDeployment(
        uid: String,
        state: String,
        target: String = "production",
        createdAt: Int = 1_700_000_000_000
    ) -> VercelDeployment {
        VercelDeployment(
            uid: uid,
            name: "web",
            url: "\(uid).vercel.app",
            state: state,
            readyState: state,
            createdAt: createdAt,
            buildingAt: nil,
            ready: nil,
            meta: nil,
            creator: nil,
            target: target
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
