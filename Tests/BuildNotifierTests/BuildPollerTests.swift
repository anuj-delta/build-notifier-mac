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
                committerName: "Anuj Sharma",
                committerEmail: "anuj.sharma@delta.exchange",
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
                committerName: "Anuj Sharma",
                committerEmail: "anuj.sharma@delta.exchange",
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
                committerName: "Anuj Sharma",
                committerEmail: "anuj.sharma@delta.exchange",
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
                committerName: "Anuj Sharma",
                committerEmail: "anuj.sharma@delta.exchange",
                workflowId: "wf-new"
            ),
            at: 0
        )
        await poller.checkNow()

        XCTAssertNotNil(appState.buildsByProject["delta-exchange/api-console"])
        XCTAssertEqual(successNotifications.map(\.buildNum), [531])
    }

    func testMineModePreservesPreviouslyVisibleWorkflowWhenActorLookupBecomesUnavailable() async throws {
        let firstPollBuilds = [
            makeBuild(
                buildNum: 530,
                branch: "main",
                committerName: "Anuj Sharma",
                committerEmail: "anuj.sharma@delta.exchange",
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
            makeBuild(buildNum: 528, branch: "feat/my-work", committerName: "Anuj Sharma", committerEmail: "anuj.sharma@delta.exchange", workflowId: "wf-feature"),
            makeBuild(buildNum: 527, branch: "feat/teammate-work", committerName: "Teammate", committerEmail: "teammate@delta.exchange", workflowId: "wf-other")
        ]

        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { workflowId in
                WorkflowDetails(id: workflowId, name: "build-and-deploy", status: "success", pipelineId: "pipeline-\(workflowId)")
            },
            fetchPipeline: { pipelineId in
                let actorLogin = pipelineId == "pipeline-wf-other" ? "teammate" : "anuj-delta"
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
                return Self.makePipeline(id: pipelineId, actorLogin: "anuj-delta")
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
            makeBuild(buildNum: 528, branch: "feat/my-work", committerName: "Anuj Sharma", committerEmail: "anuj.sharma@delta.exchange", workflowId: "wf-feature")
        ]
        let secondPollBuilds = [
            makeBuild(buildNum: 530, branch: "main", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-main"),
            makeBuild(buildNum: 528, branch: "feat/my-work", committerName: "Anuj Sharma", committerEmail: "anuj.sharma@delta.exchange", workflowId: "wf-feature")
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
                let actorLogin = pipelineId == "pipeline-wf-main" ? "anuj-delta" : "someone-else"
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
            makeBuild(buildNum: 528, branch: "feat/my-work", committerName: "Anuj Sharma", committerEmail: "anuj.sharma@delta.exchange", workflowId: "wf-feature"),
            makeBuild(buildNum: 527, branch: "feat/teammate-work", committerName: "Teammate", committerEmail: "teammate@delta.exchange", workflowId: "wf-other")
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
            makeBuild(buildNum: 11, branch: "feat/dea-367", committerName: "Anuj Sharma", committerEmail: "anuj.sharma@delta.exchange", workflowId: "wf-new", workflowName: "devnet-manual-deploy", startTime: "2026-03-24T10:00:00Z")
        ]
        let statuses = ["wf-old": "success", "wf-new": "success"]
        let appState = await runPollResolvingDeploys(builds: builds, statuses: statuses)
        XCTAssertEqual(appState.devnetDeployedBranch(forSlug: Self.slug), "feat/dea-367")
    }

    func testCanceledLatestFallsBackToEarlierSuccess() async {
        // Newest develop deploy was canceled; the prior successful one is still live.
        let builds = [
            makeBuild(buildNum: 10, branch: "develop", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-old", startTime: "2026-03-24T09:00:00Z"),
            makeBuild(buildNum: 11, branch: "develop", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-new", startTime: "2026-03-24T10:00:00Z")
        ]
        let statuses = ["wf-old": "success", "wf-new": "canceled"]
        let appState = await runPollResolvingDeploys(builds: builds, statuses: statuses)
        XCTAssertEqual(appState.devnetDeployedBranch(forSlug: Self.slug), "develop")
    }

    func testRunningDeployIsNotReportedAsDeployed() async {
        // The only deploy is still running -> nothing is live on devnet yet.
        let builds = [
            makeBuild(buildNum: 11, branch: "develop", committerName: "GitHub", committerEmail: "noreply@github.com", workflowId: "wf-run", startTime: "2026-03-24T10:00:00Z")
        ]
        let statuses = ["wf-run": "running"]
        let appState = await runPollResolvingDeploys(builds: builds, statuses: statuses)
        XCTAssertNil(appState.devnetDeployedBranch(forSlug: Self.slug))
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
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "anuj-delta") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()
        await poller.checkNow()

        XCTAssertEqual(appState.devnetDeployedBranch(forSlug: Self.slug), "develop")
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
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "anuj-delta") }
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
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "anuj-delta") }
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
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "anuj-delta") }
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
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "anuj-delta") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)

        await poller.checkNow()
        XCTAssertEqual(appState.workflowStatusByWorkflowId["wf-live"], "running")

        // Second poll's v2 fetch fails; the last-known status must survive rather than the
        // row silently dropping back to v1.1.
        await poller.checkNow()
        XCTAssertEqual(appState.workflowStatusByWorkflowId["wf-live"], "running")
    }

    private func runPollResolvingDeploys(builds: [Build], statuses: [String: String]) async -> AppState {
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in builds },
            fetchWorkflowJobs: { _ in [Self.successJob] },
            fetchWorkflow: { workflowId in
                WorkflowDetails(id: workflowId, name: "build-and-deploy", status: statuses[workflowId], pipelineId: "pipeline-\(workflowId)")
            },
            fetchPipeline: { pipelineId in Self.makePipeline(id: pipelineId, actorLogin: "anuj-delta") }
        )
        let appState = makeAppState(poller: poller, followMode: .all)
        await poller.checkNow()
        return appState
    }

    private static let slug = "delta-exchange/api-console"

    private func makeAppState(poller: BuildPoller, followMode: FollowMode) -> AppState {
        let appState = AppState(poller: poller, vercelPoller: VercelPoller(), autoApprovalPoller: AutoApprovalPoller())
        appState.currentUser = User(
            name: "Anuj Sharma",
            login: "anuj-delta",
            avatarUrl: nil,
            selectedEmail: "anuj.sharma@delta.exchange"
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
        startTime: String = "2026-03-24T10:00:00Z"
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
            lifecycle: "finished",
            outcome: "success",
            status: "success",
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
            committerName: "Anuj Sharma",
            committerEmail: "anuj.sharma@delta.exchange",
            authorName: "Anuj Sharma",
            authorEmail: "anuj.sharma@delta.exchange",
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
