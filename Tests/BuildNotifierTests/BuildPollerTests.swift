import XCTest
@testable import BuildNotifier

@MainActor
final class BuildPollerTests: XCTestCase {
    func testFailedFirstSnapshotDoesNotReplayExistingSuccessAfterRecovery() async {
        enum TestError: Error { case unavailable }

        var shouldFailBuildFetch = true
        var currentBuilds = [
            makeBuild(
                buildNum: 530,
                branch: "main",
                committerName: "Test Author",
                committerEmail: "author@example.test",
                workflowId: "wf-existing"
            )
        ]
        var successNotifications: [Build] = []
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in
                if shouldFailBuildFetch { throw TestError.unavailable }
                return currentBuilds
            },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            sendBuildSuccessNotification: { build, _ in
                successNotifications.append(build)
            }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()
        shouldFailBuildFetch = false
        await poller.checkNow()

        XCTAssertTrue(successNotifications.isEmpty)

        currentBuilds.insert(
            makeBuild(
                buildNum: 531,
                branch: "feature",
                committerName: "Test Author",
                committerEmail: "author@example.test",
                workflowId: "wf-new"
            ),
            at: 0
        )
        await poller.checkNow()

        XCTAssertNotNil(appState.buildsByProject["delta-exchange/api-console"])
        XCTAssertEqual(successNotifications.map(\.buildNum), [531])
    }

    func testFailedBaselineLookupDoesNotReplayExistingSuccessAfterRecovery() async {
        enum TestError: Error { case unavailable }

        var shouldFailWorkflowJobs = true
        var currentBuilds = [
            makeBuild(
                buildNum: 530,
                branch: "main",
                committerName: "Test Author",
                committerEmail: "author@example.test",
                workflowId: "wf-existing"
            )
        ]
        var successNotifications: [Build] = []
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in currentBuilds },
            fetchWorkflowJobs: { _ in
                if shouldFailWorkflowJobs { throw TestError.unavailable }
                return [Self.successJob]
            },
            sendBuildSuccessNotification: { build, _ in
                successNotifications.append(build)
            }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()
        shouldFailWorkflowJobs = false
        await poller.checkNow()

        XCTAssertTrue(successNotifications.isEmpty)

        currentBuilds.insert(
            makeBuild(
                buildNum: 531,
                branch: "feature",
                committerName: "Test Author",
                committerEmail: "author@example.test",
                workflowId: "wf-new"
            ),
            at: 0
        )
        await poller.checkNow()

        XCTAssertNotNil(appState.buildsByProject["delta-exchange/api-console"])
        XCTAssertEqual(successNotifications.map(\.buildNum), [531])
    }

    func testRunningWorkflowAtStartupStillNotifiesOnCompletion() async {
        var jobsAreRunning = true
        var currentBuilds = [
            makeBuild(
                buildNum: 540,
                branch: "main",
                committerName: "Test Author",
                committerEmail: "author@example.test",
                workflowId: "wf-running",
                status: "running"
            )
        ]
        var successNotifications: [Build] = []
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in currentBuilds },
            fetchWorkflowJobs: { _ in jobsAreRunning ? [Self.runningJob] : [Self.successJob] },
            sendBuildSuccessNotification: { build, _ in
                successNotifications.append(build)
            }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        // Genuinely in progress at startup: absorbed as a started baseline, not
        // parked as unresolved, so it must NOT be silently suppressed later.
        await poller.checkNow()
        XCTAssertTrue(successNotifications.isEmpty)

        // It finishes after launch: a real completion the user should hear about.
        currentBuilds = [
            makeBuild(
                buildNum: 540,
                branch: "main",
                committerName: "Test Author",
                committerEmail: "author@example.test",
                workflowId: "wf-running",
                status: "success"
            )
        ]
        jobsAreRunning = false
        await poller.checkNow()

        XCTAssertNotNil(appState.buildsByProject["delta-exchange/api-console"])
        XCTAssertEqual(successNotifications.map(\.buildNum), [540])
    }

    func testMineModePreservesPreviouslyVisibleWorkflowWhenActorLookupBecomesUnavailable() async throws {
        let firstPollBuilds = [
            makeBuild(
                buildNum: 530,
                branch: "main",
                committerName: "Test Author",
                committerEmail: "author@example.test",
                workflowId: "wf-main"
            )
        ]
        let secondPollBuilds = [
            makeBuild(
                buildNum: 530,
                branch: "main",
                committerName: "GitHub",
                committerEmail: "noreply@github.com",
                workflowId: "wf-main"
            )
        ]

        enum TestError: Error {
            case unavailable
        }

        var fetchCount = 0
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in
                fetchCount += 1
                return fetchCount == 1 ? firstPollBuilds : secondPollBuilds
            },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { _ in
                throw TestError.unavailable
            },
            fetchPipeline: { _ in
                XCTFail("Pipeline lookup should not be reached when workflow lookup fails")
                return Self.makePipeline(id: "unused", actorLogin: "unused")
            }
        )
        let appState = makeAppState(poller: poller, followMode: .mine)

        await poller.checkNow()
        await poller.checkNow()

        let trackedBuilds = try XCTUnwrap(appState.buildsByProject["delta-exchange/api-console"])
        XCTAssertEqual(trackedBuilds.map(\.branch), ["main"])
        XCTAssertEqual(trackedBuilds.first?.committerName, "GitHub")
    }

    func testMineModeIncludesBuildsTriggeredByCurrentUserActor() async throws {
        let builds = [
            makeBuild(buildNum: 530, branch: "main", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-main"),
            makeBuild(buildNum: 528, branch: "feat/my-work", committerName: "Test Author", committerEmail: "author@example.test", workflowId: "wf-feature"),
            makeBuild(buildNum: 527, branch: "feat/teammate-work", committerName: "Teammate", committerEmail: "teammate@example.test", workflowId: "wf-other")
        ]

        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { workflowId in
                WorkflowDetails(id: workflowId, name: "build-and-deploy", status: "success", pipelineId: "pipeline-\(workflowId)")
            },
            fetchPipeline: { pipelineId in
                let actorLogin = pipelineId == "pipeline-wf-other" ? "teammate" : "test-author"
                return Self.makePipeline(id: pipelineId, actorLogin: actorLogin)
            }
        )
        let appState = makeAppState(poller: poller, followMode: .mine)

        await poller.checkNow()

        let trackedBuilds = try XCTUnwrap(appState.buildsByProject["delta-exchange/api-console"])
        XCTAssertEqual(trackedBuilds.map(\.branch), ["main", "feat/my-work"])
    }

    func testMineModeCachesWorkflowOwnershipAcrossPolls() async throws {
        let builds = [
            makeBuild(buildNum: 530, branch: "main", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-main")
        ]

        var workflowFetchCount = 0
        var pipelineFetchCount = 0
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { workflowId in
                workflowFetchCount += 1
                return WorkflowDetails(id: workflowId, name: "build-and-deploy", status: "success", pipelineId: "pipeline-\(workflowId)")
            },
            fetchPipeline: { pipelineId in
                pipelineFetchCount += 1
                return Self.makePipeline(id: pipelineId, actorLogin: "test-author")
            }
        )
        let appState = makeAppState(poller: poller, followMode: .mine)

        await poller.checkNow()
        await poller.checkNow()

        let trackedBuilds = try XCTUnwrap(appState.buildsByProject["delta-exchange/api-console"])
        XCTAssertEqual(trackedBuilds.map(\.branch), ["main"])
        // Two first-poll workflow fetches - one for actor ownership, one for the row's v2
        // status - then both are cached, so the second poll adds none.
        XCTAssertEqual(workflowFetchCount, 2)
        XCTAssertEqual(pipelineFetchCount, 1)
    }

    func testMineModeSendsPendingApprovalNotificationForActorMatchedWorkflow() async {
        let firstPollBuilds = [
            makeBuild(buildNum: 528, branch: "feat/my-work", committerName: "Test Author", committerEmail: "author@example.test", workflowId: "wf-feature")
        ]
        let secondPollBuilds = [
            makeBuild(buildNum: 530, branch: "main", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-main"),
            makeBuild(buildNum: 528, branch: "feat/my-work", committerName: "Test Author", committerEmail: "author@example.test", workflowId: "wf-feature")
        ]

        var fetchCount = 0
        var approvalNotifications: [PendingApproval] = []
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in
                fetchCount += 1
                return fetchCount == 1 ? firstPollBuilds : secondPollBuilds
            },
            fetchWorkflowJobs: { workflowId in
                if workflowId == "wf-main" {
                    return [
                        WorkflowJob(
                            id: "approval-1",
                            name: "prod approval",
                            projectSlug: "gh/delta-exchange/api-console",
                            status: "on_hold",
                            type: "approval",
                            approvedBy: nil,
                            startedAt: nil,
                            stoppedAt: nil,
                            jobNumber: 530
                        )
                    ]
                }
                return [Self.successJob]
            },
            fetchWorkflow: { workflowId in
                WorkflowDetails(id: workflowId, name: "build-and-deploy", status: "on_hold", pipelineId: "pipeline-\(workflowId)")
            },
            fetchPipeline: { pipelineId in
                let actorLogin = pipelineId == "pipeline-wf-main" ? "test-author" : "someone-else"
                return Self.makePipeline(id: pipelineId, actorLogin: actorLogin)
            },
            sendPendingApprovalNotification: { approval, _ in
                approvalNotifications.append(approval)
            }
        )
        let appState = makeAppState(poller: poller, followMode: .mine)
        appState.preferences.notifyOnSuccess = false
        appState.preferences.notifyOnFailure = false
        appState.preferences.notifyOnBuildStarted = false

        await poller.checkNow()
        await poller.checkNow()

        XCTAssertEqual(appState.pendingApprovals.count, 1)
        XCTAssertEqual(appState.pendingApprovals.first?.build.branch, "main")
        XCTAssertEqual(approvalNotifications.count, 1)
        XCTAssertEqual(approvalNotifications.first?.build.branch, "main")
    }

    func testAllModeStillReturnsAllRecentBuilds() async throws {
        let builds = [
            makeBuild(buildNum: 530, branch: "main", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-main"),
            makeBuild(buildNum: 529, branch: "develop", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-develop"),
            makeBuild(buildNum: 528, branch: "feat/my-work", committerName: "Test Author", committerEmail: "author@example.test", workflowId: "wf-feature"),
            makeBuild(buildNum: 527, branch: "feat/teammate-work", committerName: "Teammate", committerEmail: "teammate@example.test", workflowId: "wf-other")
        ]

        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { workflowId in
                WorkflowDetails(id: workflowId, name: "build-and-deploy", status: "success", pipelineId: "pipeline-\(workflowId)")
            },
            fetchPipeline: { pipelineId in
                Self.makePipeline(id: pipelineId, actorLogin: "someone-else")
            }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()

        let trackedBuilds = try XCTUnwrap(appState.buildsByProject["delta-exchange/api-console"])
        XCTAssertEqual(trackedBuilds.map(\.branch), ["main", "develop", "feat/my-work", "feat/teammate-work"])
    }

    // MARK: - Devnet deployed branch (v2 workflow status)

    func testDevnetDeployedBranchIsNewestSuccessfulWorkflow() async {
        let builds = [
            makeBuild(buildNum: 10, branch: "develop", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-old", startTime: "2026-03-24T09:00:00Z"),
            makeBuild(buildNum: 11, branch: "feat/dea-367", committerName: "Test Author", committerEmail: "author@example.test", workflowId: "wf-new", workflowName: "devnet-manual-deploy", startTime: "2026-03-24T10:00:00Z")
        ]
        let statuses = ["wf-old": "success", "wf-new": "success"]
        let appState = await runPollResolvingDeploys(builds: builds, statuses: statuses)
        XCTAssertEqual(appState.deployedBranch(forSlug: Self.slug, env: .devnet), "feat/dea-367")
    }

    func testCanceledLatestFallsBackToEarlierSuccess() async {
        // Newest develop deploy was canceled; the prior successful one is still live.
        let builds = [
            makeBuild(buildNum: 10, branch: "develop", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-old", startTime: "2026-03-24T09:00:00Z"),
            makeBuild(buildNum: 11, branch: "develop", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-new", startTime: "2026-03-24T10:00:00Z")
        ]
        let statuses = ["wf-old": "success", "wf-new": "canceled"]
        let appState = await runPollResolvingDeploys(builds: builds, statuses: statuses)
        XCTAssertEqual(appState.deployedBranch(forSlug: Self.slug, env: .devnet), "develop")
    }

    func testRunningDeployIsNotReportedAsDeployed() async {
        // The only deploy is still running -> nothing is live on devnet yet.
        let builds = [
            makeBuild(buildNum: 11, branch: "develop", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-run", startTime: "2026-03-24T10:00:00Z")
        ]
        let statuses = ["wf-run": "running"]
        let appState = await runPollResolvingDeploys(builds: builds, statuses: statuses)
        XCTAssertNil(appState.deployedBranch(forSlug: Self.slug, env: .devnet))
    }

    func testTerminalWorkflowStatusIsCachedAcrossPolls() async {
        let builds = [
            makeBuild(buildNum: 11, branch: "develop", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-dep", startTime: "2026-03-24T10:00:00Z")
        ]
        var statusFetches: [String: Int] = [:]
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { workflowId in
                statusFetches[workflowId, default: 0] += 1
                return WorkflowDetails(id: workflowId, name: "build-and-deploy", status: "success", pipelineId: "pipeline-\(workflowId)")
            },
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "test-author") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()
        await poller.checkNow()

        XCTAssertEqual(appState.deployedBranch(forSlug: Self.slug, env: .devnet), "develop")
        // success is terminal, so the workflow status is fetched once and cached.
        XCTAssertEqual(statusFetches["wf-dep"], 1)
    }

    // MARK: - Row status (v2 workflow rollup)

    func testRowWorkflowStatusIsResolvedFromV2ForOnScreenBranches() async {
        // v1.1 still says the job is running; v2 has already rolled up to success. The row
        // must trust v2, so the resolved status - not the stale v1.1 one - drives the glyph.
        let builds = [
            makeRunningV1Build(branch: "feat/dea-201", workflowId: "wf-live")
        ]
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { workflowId in
                WorkflowDetails(id: workflowId, name: "devnet-manual-deploy", status: "success", pipelineId: "pipeline-\(workflowId)")
            },
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "test-author") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()

        XCTAssertEqual(appState.workflowStatusByWorkflowId["wf-live"], "success")
        XCTAssertEqual(RowStatus(circleCIWorkflowStatus: "success"), .success)
    }

    func testRowWorkflowStatusOmitsWorkflowWhenV2FetchFails() async {
        enum TestError: Error { case unavailable }
        let builds = [
            makeRunningV1Build(branch: "feat/dea-201", workflowId: "wf-live")
        ]
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { _ in throw TestError.unavailable },
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "test-author") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()

        // No v2 status -> row falls back to v1.1 rather than showing a stale/empty state.
        XCTAssertNil(appState.workflowStatusByWorkflowId["wf-live"])
    }

    func testDevnetCandidateRowFetchesV2StatusOncePerPoll() async {
        // A still-running devnet workflow is both a deploy candidate and an on-screen row.
        // The devnet resolver and the row-status resolver must share the per-poll fetch so
        // it makes a single v2 round-trip, not two.
        let builds = [
            makeBuild(buildNum: 11, branch: "develop", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-run", startTime: "2026-03-24T10:00:00Z")
        ]
        var statusFetches: [String: Int] = [:]
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { workflowId in
                statusFetches[workflowId, default: 0] += 1
                return WorkflowDetails(id: workflowId, name: "build-and-deploy", status: "running", pipelineId: "pipeline-\(workflowId)")
            },
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "test-author") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()

        XCTAssertEqual(statusFetches["wf-run"], 1)
        XCTAssertEqual(appState.workflowStatusByWorkflowId["wf-run"], "running")
    }

    func testOnScreenWorkflowStatusIsPreservedOnTransientV2Failure() async {
        enum TestError: Error { case unavailable }
        let builds = [
            makeRunningV1Build(branch: "feat/dea-201", workflowId: "wf-live")
        ]
        var fetchCount = 0
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { workflowId in
                fetchCount += 1
                if fetchCount == 1 {
                    return WorkflowDetails(id: workflowId, name: "devnet-manual-deploy", status: "running", pipelineId: "pipeline-\(workflowId)")
                }
                throw TestError.unavailable
            },
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "test-author") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()
        XCTAssertEqual(appState.workflowStatusByWorkflowId["wf-live"], "running")

        // Second poll's v2 fetch fails; the last-known status must survive rather than the
        // row silently dropping back to v1.1.
        await poller.checkNow()
        XCTAssertEqual(appState.workflowStatusByWorkflowId["wf-live"], "running")
    }

    // MARK: - Stuck workflow rollup (stopped but non-terminal status)

    func testStoppedWorkflowWithStuckRunningRollupResolvesToSuccessFromJobs() async {
        // CircleCI's rollup can stay "running" after a rerun-from-failed even though the
        // workflow stopped and every job is done. The row must not spin forever: with
        // stopped_at set, the true status is derived from the jobs.
        let builds = [
            makeRunningV1Build(branch: "INFRA-782/sigma-chatbot", workflowId: "wf-stuck")
        ]
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { workflowId in
                WorkflowDetails(id: workflowId, name: "sigma-manual-deploy", status: "running", pipelineId: "pipeline-\(workflowId)", stoppedAt: "2026-07-15T04:42:49Z")
            },
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "test-author") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()

        XCTAssertEqual(appState.workflowStatusByWorkflowId["wf-stuck"], "success")
    }

    func testStoppedWorkflowWithFailedJobResolvesToFailed() async {
        let builds = [
            makeRunningV1Build(branch: "feat/x", workflowId: "wf-stuck")
        ]
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob, Self.failedJob] },
            fetchWorkflow: { workflowId in
                WorkflowDetails(id: workflowId, name: "sigma-manual-deploy", status: "failing", pipelineId: "pipeline-\(workflowId)", stoppedAt: "2026-07-15T04:42:49Z")
            },
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "test-author") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()

        XCTAssertEqual(appState.workflowStatusByWorkflowId["wf-stuck"], "failed")
    }

    func testRunningWorkflowWithoutStoppedAtStaysRunning() async {
        // A genuinely in-progress workflow (no stopped_at) must keep spinning, not be
        // second-guessed by the job list.
        let builds = [
            makeRunningV1Build(branch: "feat/x", workflowId: "wf-live")
        ]
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { workflowId in
                WorkflowDetails(id: workflowId, name: "sigma-manual-deploy", status: "running", pipelineId: "pipeline-\(workflowId)", stoppedAt: nil)
            },
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "test-author") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()

        XCTAssertEqual(appState.workflowStatusByWorkflowId["wf-live"], "running")
    }

    // MARK: - Sigma deployed branch

    func testSigmaDeployedBranchResolvesFromSigmaWorkflow() async {
        let builds = [
            makeBuild(buildNum: 11, branch: "INFRA-782/sigma-chatbot", committerName: "Colleague", committerEmail: "colleague@example.test", workflowId: "wf-sigma", workflowName: "sigma-manual-deploy", startTime: "2026-07-15T04:41:58Z")
        ]
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { workflowId in
                WorkflowDetails(id: workflowId, name: "sigma-manual-deploy", status: "success", pipelineId: "pipeline-\(workflowId)")
            },
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "test-author") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()

        XCTAssertEqual(appState.deployedBranch(forSlug: Self.slug, env: .sigma), "INFRA-782/sigma-chatbot")
        // The devnet badge must not fire for a sigma-only deploy.
        XCTAssertNil(appState.deployedBranch(forSlug: Self.slug, env: .devnet))
    }

    func testStoppedWorkflowWithStillRunningJobKeepsOriginalStatus() async {
        // Defensive: stopped_at is set but a job still reads running (API divergence). We must
        // not claim success - keep the original rollup status.
        let builds = [
            makeRunningV1Build(branch: "feat/x", workflowId: "wf-stuck")
        ]
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob, Self.runningJob] },
            fetchWorkflow: { workflowId in
                WorkflowDetails(id: workflowId, name: "sigma-manual-deploy", status: "running", pipelineId: "pipeline-\(workflowId)", stoppedAt: "2026-07-15T04:42:49Z")
            },
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "test-author") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()

        XCTAssertEqual(appState.workflowStatusByWorkflowId["wf-stuck"], "running")
    }

    func testRerunWorkflowWithNullStoppedAtResolvesFromJobs() async {
        // A rerun-from-failed can leave the rollup stuck "running" with stopped_at never set,
        // even though every job succeeded. The tag is the only "it's actually a finished rerun"
        // signal, so the row must resolve from jobs rather than spin forever.
        let builds = [
            makeRunningV1Build(branch: "main", workflowId: "wf-rerun")
        ]
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { workflowId in
                WorkflowDetails(id: workflowId, name: "build-and-deploy", status: "running", pipelineId: "pipeline-\(workflowId)", stoppedAt: nil, tag: "rerun-workflow-from-failed")
            },
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "test-author") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()

        XCTAssertEqual(appState.workflowStatusByWorkflowId["wf-rerun"], "success")
    }

    func testRerunWorkflowWithRunningJobStaysRunning() async {
        // A rerun that is genuinely still in flight (a job is running, stopped_at unset) must
        // keep spinning - the job-derivation must not prematurely claim a terminal status.
        let builds = [
            makeRunningV1Build(branch: "main", workflowId: "wf-rerun")
        ]
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob, Self.runningJob] },
            fetchWorkflow: { workflowId in
                WorkflowDetails(id: workflowId, name: "build-and-deploy", status: "running", pipelineId: "pipeline-\(workflowId)", stoppedAt: nil, tag: "rerun-workflow-from-start")
            },
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "test-author") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()

        XCTAssertEqual(appState.workflowStatusByWorkflowId["wf-rerun"], "running")
    }

    // MARK: - Deployed branch pinned past the branch cap

    func testDeployedBranchPinnedIntoMenuPastBranchCap() async {
        // Five recently-active branches fill the cap; a sigma-deployed branch older than all of
        // them would normally be dropped. It must be pinned in so its badge still renders.
        let recent = (0..<5).map { i in
            makeBuild(
                buildNum: 100 + i,
                branch: "feat/recent-\(i)",
                committerName: "GitHub",
                committerEmail: "noreply@github.com",
                workflowId: "wf-recent-\(i)",
                startTime: "2026-07-24T1\(i):00:00Z"
            )
        }
        let sigmaBuild = makeBuild(
            buildNum: 5,
            branch: "INFRA-782/sigma-chatbot",
            committerName: "Colleague",
            committerEmail: "colleague@example.test",
            workflowId: "wf-sigma",
            workflowName: "sigma-manual-deploy",
            startTime: "2026-07-20T01:00:00Z"
        )
        let builds = recent + [sigmaBuild]
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { workflowId in
                let name = workflowId == "wf-sigma" ? "sigma-manual-deploy" : "build-and-deploy"
                return WorkflowDetails(id: workflowId, name: name, status: "success", pipelineId: "pipeline-\(workflowId)")
            },
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "test-author") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()

        XCTAssertEqual(appState.deployedBranch(forSlug: Self.slug, env: .sigma), "INFRA-782/sigma-chatbot")

        let branches = Set((appState.groupedBuilds.first?.builds ?? [:]).keys)
        XCTAssertTrue(branches.contains("INFRA-782/sigma-chatbot"))
        XCTAssertEqual(branches.count, 6)
    }

    // MARK: - Deploying (in-flight) state

    func testRunningDeployShowsDeployingNotDeployed() async {
        let builds = [
            makeBuild(buildNum: 11, branch: "develop", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-run", startTime: "2026-03-24T10:00:00Z")
        ]
        let statuses = ["wf-run": "running"]
        let appState = await runPollResolvingDeploys(builds: builds, statuses: statuses)
        XCTAssertEqual(appState.deployingBranch(forSlug: Self.slug, env: .devnet), "develop")
        XCTAssertNil(appState.deployedBranch(forSlug: Self.slug, env: .devnet))
    }

    func testConcurrentSuccessAndRunningDeployReportBothBranches() async {
        // develop is live; a newer manual deploy of a feature branch is still running.
        let builds = [
            makeBuild(buildNum: 10, branch: "develop", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-live", startTime: "2026-03-24T09:00:00Z"),
            makeBuild(buildNum: 11, branch: "feat/dea-367", committerName: "Test Author", committerEmail: "author@example.test", workflowId: "wf-run", workflowName: "devnet-manual-deploy", startTime: "2026-03-24T10:00:00Z")
        ]
        let statuses = ["wf-live": "success", "wf-run": "running"]
        let appState = await runPollResolvingDeploys(builds: builds, statuses: statuses)
        XCTAssertEqual(appState.deployedBranch(forSlug: Self.slug, env: .devnet), "develop")
        XCTAssertEqual(appState.deployingBranch(forSlug: Self.slug, env: .devnet), "feat/dea-367")
    }

    func testFailedDeployFallsBackToPreviousDeployedBranch() async {
        // The newest deploy failed; the row keeps showing the last branch that went live and
        // shows no in-flight state.
        let builds = [
            makeBuild(buildNum: 10, branch: "develop", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-live", startTime: "2026-03-24T09:00:00Z"),
            makeBuild(buildNum: 11, branch: "feat/dea-367", committerName: "Test Author", committerEmail: "author@example.test", workflowId: "wf-fail", workflowName: "devnet-manual-deploy", startTime: "2026-03-24T10:00:00Z")
        ]
        let statuses = ["wf-live": "success", "wf-fail": "failed"]
        let appState = await runPollResolvingDeploys(builds: builds, statuses: statuses)
        XCTAssertEqual(appState.deployedBranch(forSlug: Self.slug, env: .devnet), "develop")
        XCTAssertNil(appState.deployingBranch(forSlug: Self.slug, env: .devnet))
    }

    func testDeployingClearsOnceDeploySucceeds() async {
        // First poll: deploy is running (in-flight, not live). Second poll: it succeeded, so it
        // becomes live and the in-flight marker clears.
        let builds = [
            makeBuild(buildNum: 11, branch: "feat/dea-367", committerName: "Test Author", committerEmail: "author@example.test", workflowId: "wf-x", workflowName: "devnet-manual-deploy", startTime: "2026-03-24T10:00:00Z")
        ]
        var status = "running"
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { workflowId in
                WorkflowDetails(id: workflowId, name: "devnet-manual-deploy", status: status, pipelineId: "pipeline-\(workflowId)")
            },
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "test-author") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()
        XCTAssertEqual(appState.deployingBranch(forSlug: Self.slug, env: .devnet), "feat/dea-367")
        XCTAssertNil(appState.deployedBranch(forSlug: Self.slug, env: .devnet))

        status = "success"
        await poller.checkNow()
        XCTAssertNil(appState.deployingBranch(forSlug: Self.slug, env: .devnet))
        XCTAssertEqual(appState.deployedBranch(forSlug: Self.slug, env: .devnet), "feat/dea-367")
    }

    func testDeployingBadgePreservedWhenProjectFetchFails() async {
        enum TestError: Error { case unavailable }
        let builds = [
            makeBuild(buildNum: 11, branch: "develop", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-run", startTime: "2026-03-24T10:00:00Z")
        ]
        var shouldFail = false
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in
                if shouldFail { throw TestError.unavailable }
                return builds
            },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { workflowId in
                WorkflowDetails(id: workflowId, name: "build-and-deploy", status: "running", pipelineId: "pipeline-\(workflowId)")
            },
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "test-author") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()
        XCTAssertEqual(appState.deployingBranch(forSlug: Self.slug, env: .devnet), "develop")

        // The next poll's build fetch fails; the project drops out of the results, but its
        // in-flight badge must survive rather than flicker off.
        shouldFail = true
        await poller.checkNow()
        XCTAssertEqual(appState.deployingBranch(forSlug: Self.slug, env: .devnet), "develop")
    }

    private func runPollResolvingDeploys(builds: [Build], statuses: [String: String]) async -> AppState {
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { workflowId in
                WorkflowDetails(id: workflowId, name: "build-and-deploy", status: statuses[workflowId], pipelineId: "pipeline-\(workflowId)")
            },
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "test-author") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)
        await poller.checkNow()
        return appState
    }

    private static let slug = "delta-exchange/api-console"

    private func makeAppState(poller: BuildPoller, followMode: FollowMode) -> AppState {
        let appState = AppState(poller: poller, vercelPoller: VercelPoller(), autoApprovalPoller: AutoApprovalPoller())
        appState.currentUser = User(
            name: "Test Author",
            login: "test-author",
            avatarUrl: nil,
            selectedEmail: "author@example.test"
        )
        appState.preferences.watchedProjects = [
            WatchedProject(
                id: "gh/delta-exchange/api-console",
                vcsType: "gh",
                orgName: "delta-exchange",
                repoName: "api-console",
                followMode: followMode,
                isEnabled: true
            )
        ]
        return appState
    }

    private func makeBuild(
        buildNum: Int,
        branch: String,
        committerName: String,
        committerEmail: String,
        workflowId: String,
        workflowName: String = "build-and-deploy",
        startTime: String = "2026-03-24T10:00:00Z",
        status: String = "success"
    ) -> Build {
        Build(
            vcsUrl: "https://github.com/delta-exchange/api-console",
            buildUrl: "https://circleci.com/gh/delta-exchange/api-console/\(buildNum)",
            buildNum: buildNum,
            branch: branch,
            vcsRevision: "rev-\(buildNum)",
            committerName: committerName,
            committerEmail: committerEmail,
            authorName: committerName,
            authorEmail: committerEmail,
            subject: "Commit \(buildNum)",
            body: nil,
            why: "github",
            queuedAt: startTime,
            startTime: startTime,
            stopTime: "2026-03-24T10:05:00Z",
            buildTimeMillis: 300000,
            username: "delta-exchange",
            reponame: "api-console",
            lifecycle: status == "success" ? "finished" : "running",
            outcome: status == "success" ? "success" : nil,
            status: status,
            retryOf: nil,
            workflows: WorkflowInfo(
                jobName: "job-\(buildNum)",
                workflowId: workflowId,
                workflowName: workflowName
            ),
            pullRequests: nil
        )
    }

    /// A v1.1 build still reporting itself as running - the lagging state that leaves a row
    /// spinning after the workflow has actually finished per v2.
    private func makeRunningV1Build(branch: String, workflowId: String) -> Build {
        Build(
            vcsUrl: "https://github.com/delta-exchange/api-console",
            buildUrl: "https://circleci.com/gh/delta-exchange/api-console/1",
            buildNum: 1,
            branch: branch,
            vcsRevision: "rev-1",
            committerName: "Test Author",
            committerEmail: "author@example.test",
            authorName: "Test Author",
            authorEmail: "author@example.test",
            subject: "Commit 1",
            body: nil,
            why: "github",
            queuedAt: "2026-07-13T10:00:00Z",
            startTime: "2026-07-13T10:00:00Z",
            stopTime: nil,
            buildTimeMillis: nil,
            username: "delta-exchange",
            reponame: "api-console",
            lifecycle: "running",
            outcome: nil,
            status: "running",
            retryOf: nil,
            workflows: WorkflowInfo(jobName: "job-1", workflowId: workflowId, workflowName: "devnet-manual-deploy"),
            pullRequests: nil
        )
    }

    private static let successJob = WorkflowJob(
        id: "job-success",
        name: "build",
        projectSlug: "gh/delta-exchange/api-console",
        status: "success",
        type: "build",
        approvedBy: nil,
        startedAt: nil,
        stoppedAt: nil,
        jobNumber: 1
    )

    private static let runningJob = WorkflowJob(
        id: "job-running",
        name: "build",
        projectSlug: "gh/delta-exchange/api-console",
        status: "running",
        type: "build",
        approvedBy: nil,
        startedAt: nil,
        stoppedAt: nil,
        jobNumber: 1
    )

    private static let failedJob = WorkflowJob(
        id: "job-failed",
        name: "build",
        projectSlug: "gh/delta-exchange/api-console",
        status: "failed",
        type: "build",
        approvedBy: nil,
        startedAt: nil,
        stoppedAt: nil,
        jobNumber: 1
    )

    private static func makePipeline(id: String, actorLogin: String) -> PipelineDetails {
        PipelineDetails(
            id: id,
            state: "created",
            trigger: PipelineTrigger(
                type: "webhook",
                actor: PipelineActor(login: actorLogin, name: nil, avatarUrl: nil),
                receivedAt: nil
            ),
            vcs: PipelineVCS(branch: "main")
        )
    }
}
