import XCTest
@testable import BuildNotifier

@MainActor
final class BuildPollerTests: XCTestCase {
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
        XCTAssertEqual(workflowFetchCount, 1)
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
        workflowId: String
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
            queuedAt: "2026-03-24T10:00:00Z",
            startTime: "2026-03-24T10:00:00Z",
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
                workflowName: "build-and-deploy"
            ),
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
