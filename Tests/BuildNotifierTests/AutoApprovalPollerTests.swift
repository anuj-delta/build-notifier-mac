import XCTest
@testable import BuildNotifier

@MainActor
final class AutoApprovalPollerTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "UserPreferences")
        super.tearDown()
    }

    func testArmingSameWorkflowIsIdempotent() {
        let poller = AutoApprovalPoller(
            fetchWorkflowJobs: { _ in [] },
            approvePendingJob: { _, _ in }
        )
        let appState = AppState(autoApprovalPoller: poller)
        let build = makeBuild()
        appState.recordWorkflowApprovalSupport(workflowId: "workflow-1", jobs: [makeApprovalGate(status: "not_run")])

        appState.armAutoApprove(for: build)
        appState.armAutoApprove(for: build)

        XCTAssertEqual(appState.armedAutoApprovals.count, 1)
        XCTAssertEqual(appState.armedAutoApprovals["workflow-1"]?.buildNumber, 42)
    }

    func testCancelAutoApproveRemovesOnlyTargetWorkflow() {
        let poller = AutoApprovalPoller(
            fetchWorkflowJobs: { _ in [] },
            approvePendingJob: { _, _ in }
        )
        let appState = AppState(autoApprovalPoller: poller)
        appState.recordWorkflowApprovalSupport(workflowId: "workflow-1", jobs: [makeApprovalGate(status: "not_run")])
        appState.recordWorkflowApprovalSupport(workflowId: "workflow-2", jobs: [makeApprovalGate(status: "not_run")])

        appState.armAutoApprove(for: makeBuild(workflowId: "workflow-1", buildNum: 1))
        appState.armAutoApprove(for: makeBuild(workflowId: "workflow-2", buildNum: 2))

        appState.cancelAutoApprove(forWorkflowId: "workflow-1")

        XCTAssertNil(appState.armedAutoApprovals["workflow-1"])
        XCTAssertNotNil(appState.armedAutoApprovals["workflow-2"])
    }

    func testSessionOnlyAutoApprovalsAreNotPersistedInPreferences() {
        let poller = AutoApprovalPoller(
            fetchWorkflowJobs: { _ in [] },
            approvePendingJob: { _, _ in }
        )
        let appState = AppState(autoApprovalPoller: poller)
        appState.recordWorkflowApprovalSupport(workflowId: "workflow-1", jobs: [makeApprovalGate(status: "not_run")])

        appState.armAutoApprove(for: makeBuild())
        appState.preferences.notificationsEnabled = false
        appState.savePreferences()

        let reloadedAppState = AppState(autoApprovalPoller: poller)

        XCTAssertEqual(UserPreferences.load().notificationsEnabled, false)
        XCTAssertTrue(reloadedAppState.armedAutoApprovals.isEmpty)
        XCTAssertTrue(reloadedAppState.workflowApprovalSupport.isEmpty)
    }

    func testPendingApprovalTriggersApprovalRefreshAndNotification() async {
        var approvedRequests: [(String, String)] = []
        var sentNotifications: [(String, String)] = []
        var refreshed = 0

        let poller = AutoApprovalPoller(
            fetchWorkflowJobs: { _ in
                [makeApprovalGate(id: "approval-job-1", name: "Deploy approval", status: "on_hold")]
            },
            approvePendingJob: { workflowId, approvalRequestId in
                approvedRequests.append((workflowId, approvalRequestId))
            },
            sendAutoApprovedNotification: { armedApproval, jobName, _ in
                sentNotifications.append((armedApproval.workflowId, jobName))
            },
            requestBuildRefresh: { _ in
                refreshed += 1
            }
        )
        let appState = AppState(autoApprovalPoller: poller)
        appState.recordWorkflowApprovalSupport(workflowId: "workflow-1", jobs: [makeApprovalGate(status: "not_run")])

        appState.armAutoApprove(for: makeBuild())
        await poller.checkNow()

        XCTAssertEqual(approvedRequests.count, 1)
        XCTAssertEqual(approvedRequests.first?.0, "workflow-1")
        XCTAssertEqual(approvedRequests.first?.1, "approval-job-1")
        XCTAssertEqual(sentNotifications.count, 1)
        XCTAssertEqual(sentNotifications.first?.0, "workflow-1")
        XCTAssertEqual(sentNotifications.first?.1, "Deploy approval")
        XCTAssertEqual(refreshed, 1)
    }

    func testEveryGateWaitingInTheWorkflowIsApproved() async {
        var approvedJobIds: [String] = []
        var sentNotifications: [String] = []
        var refreshed = 0

        let poller = AutoApprovalPoller(
            fetchWorkflowJobs: { _ in
                [
                    makeApprovalGate(id: "gate-sidekiq", name: "deploy-approval-ind-sidekiq", status: "on_hold"),
                    makeApprovalGate(id: "gate-rails", name: "deploy-approval-ind-rails", status: "on_hold")
                ]
            },
            approvePendingJob: { _, approvalRequestId in
                approvedJobIds.append(approvalRequestId)
            },
            sendAutoApprovedNotification: { _, jobName, _ in
                sentNotifications.append(jobName)
            },
            requestBuildRefresh: { _ in
                refreshed += 1
            }
        )
        let appState = AppState(autoApprovalPoller: poller)
        appState.recordWorkflowApprovalSupport(workflowId: "workflow-1", jobs: [makeApprovalGate(status: "not_run")])

        appState.armAutoApprove(for: makeBuild())
        await poller.checkNow()

        XCTAssertEqual(approvedJobIds, ["gate-sidekiq", "gate-rails"])
        XCTAssertEqual(sentNotifications, ["deploy-approval-ind-sidekiq", "deploy-approval-ind-rails"])
        XCTAssertEqual(refreshed, 1)
    }

    /// A gate keeps reporting `on_hold` for a few seconds after it is approved, so the next
    /// poll must not approve it again and announce it twice.
    func testGateApprovedOnceIsNotApprovedAgainOnTheNextPoll() async {
        var approvedRequests = 0
        var sentNotifications = 0

        let poller = AutoApprovalPoller(
            fetchWorkflowJobs: { _ in
                [
                    makeApprovalGate(id: "gate-1", status: "on_hold"),
                    makeWorkflowJob(id: "deploy-1", name: "Deploy", status: "running")
                ]
            },
            approvePendingJob: { _, _ in
                approvedRequests += 1
            },
            sendAutoApprovedNotification: { _, _, _ in
                sentNotifications += 1
            }
        )
        let appState = AppState(autoApprovalPoller: poller)
        appState.recordWorkflowApprovalSupport(workflowId: "workflow-1", jobs: [makeApprovalGate(status: "not_run")])

        appState.armAutoApprove(for: makeBuild())
        await poller.checkNow()
        await poller.checkNow()

        XCTAssertEqual(approvedRequests, 1)
        XCTAssertEqual(sentNotifications, 1)
    }

    func testArmStaysWhileTheWorkflowCanStillAskForApproval() async {
        var approvedRequests = 0

        let poller = AutoApprovalPoller(
            fetchWorkflowJobs: { _ in
                [
                    makeApprovalGate(id: "gate-1", status: "success", approvedBy: "user-123"),
                    makeWorkflowJob(id: "deploy-1", name: "Deploy", status: "running"),
                    makeApprovalGate(id: "gate-2", status: "blocked")
                ]
            },
            approvePendingJob: { _, _ in
                approvedRequests += 1
            }
        )
        let appState = AppState(autoApprovalPoller: poller)
        appState.recordWorkflowApprovalSupport(workflowId: "workflow-1", jobs: [makeApprovalGate(status: "not_run")])

        appState.armAutoApprove(for: makeBuild())
        await poller.checkNow()

        XCTAssertEqual(approvedRequests, 0)
        XCTAssertNotNil(appState.armedAutoApprovals["workflow-1"])
    }

    func testArmClearsOnceTheWorkflowIsDone() async {
        let poller = AutoApprovalPoller(
            fetchWorkflowJobs: { _ in
                [
                    makeApprovalGate(id: "gate-1", status: "success", approvedBy: "user-123"),
                    makeWorkflowJob(id: "deploy-1", name: "Deploy", status: "success")
                ]
            },
            approvePendingJob: { _, _ in }
        )
        let appState = AppState(autoApprovalPoller: poller)
        appState.recordWorkflowApprovalSupport(workflowId: "workflow-1", jobs: [makeApprovalGate(status: "not_run")])

        appState.armAutoApprove(for: makeBuild())
        await poller.checkNow()

        XCTAssertTrue(appState.armedAutoApprovals.isEmpty)
    }

    func testGateCircleCIRefusesIsNotAnnouncedAndKeepsTheArm() async {
        var sentNotifications = 0
        var refreshed = 0

        let poller = AutoApprovalPoller(
            fetchWorkflowJobs: { _ in
                [makeApprovalGate(id: "gate-1", status: "on_hold")]
            },
            approvePendingJob: { _, _ in
                throw CircleCIError.httpError(400, "Job is not awaiting approval")
            },
            sendAutoApprovedNotification: { _, _, _ in
                sentNotifications += 1
            },
            requestBuildRefresh: { _ in
                refreshed += 1
            }
        )
        let appState = AppState(autoApprovalPoller: poller)
        appState.recordWorkflowApprovalSupport(workflowId: "workflow-1", jobs: [makeApprovalGate(status: "not_run")])

        appState.armAutoApprove(for: makeBuild())
        await poller.checkNow()

        XCTAssertEqual(sentNotifications, 0)
        XCTAssertEqual(refreshed, 0)
        XCTAssertNotNil(appState.armedAutoApprovals["workflow-1"])
        XCTAssertNil(poller.error)
    }

    func testTransientErrorsKeepArmedApprovalForRetry() async {
        enum TestError: Error {
            case network
        }

        let poller = AutoApprovalPoller(
            fetchWorkflowJobs: { _ in
                throw TestError.network
            },
            approvePendingJob: { _, _ in }
        )
        let appState = AppState(autoApprovalPoller: poller)
        appState.recordWorkflowApprovalSupport(workflowId: "workflow-1", jobs: [makeApprovalGate(status: "not_run")])

        appState.armAutoApprove(for: makeBuild())
        await poller.checkNow()

        XCTAssertNotNil(appState.armedAutoApprovals["workflow-1"])
    }

    func testArmAutoApproveRequiresConfirmedApprovalSupport() {
        let poller = AutoApprovalPoller(
            fetchWorkflowJobs: { _ in [] },
            approvePendingJob: { _, _ in }
        )
        let appState = AppState(autoApprovalPoller: poller)

        appState.armAutoApprove(for: makeBuild())

        XCTAssertTrue(appState.armedAutoApprovals.isEmpty)
    }
}

private func makeBuild(
    workflowId: String = "workflow-1",
    buildNum: Int = 42
) -> Build {
    Build(
        vcsUrl: "https://github.com/org/repo",
        buildUrl: "https://app.circleci.com/pipelines/workflows/\(workflowId)",
        buildNum: buildNum,
        branch: "main",
        vcsRevision: "abc123",
        committerName: "Dev",
        committerEmail: "dev@example.com",
        authorName: "Dev",
        authorEmail: "dev@example.com",
        subject: "Ship it",
        body: nil,
        why: nil,
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
        workflows: WorkflowInfo(
            jobName: "deploy",
            workflowId: workflowId,
            workflowName: "deploy-workflow"
        ),
        pullRequests: nil
    )
}

private func makeApprovalGate(
    id: String = "approval-job",
    name: String = "Deploy approval",
    status: String,
    approvedBy: String? = nil
) -> WorkflowJob {
    makeWorkflowJob(id: id, name: name, status: status, type: "approval", approvedBy: approvedBy)
}

private func makeWorkflowJob(
    id: String,
    name: String,
    status: String,
    type: String? = nil,
    approvedBy: String? = nil
) -> WorkflowJob {
    WorkflowJob(
        id: id,
        name: name,
        projectSlug: "gh/org/repo",
        status: status,
        type: type,
        approvedBy: approvedBy,
        startedAt: nil,
        stoppedAt: nil,
        jobNumber: 10
    )
}
