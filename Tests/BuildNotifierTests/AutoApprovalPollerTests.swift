import XCTest
@testable import BuildNotifier
@testable import BuildNotifierCore

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
        appState.recordWorkflowApprovalSupport(workflowId: "workflow-1", jobs: [makeWorkflowJob(type: "approval", status: "not_run")])

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
        appState.recordWorkflowApprovalSupport(workflowId: "workflow-1", jobs: [makeWorkflowJob(type: "approval", status: "not_run")])
        appState.recordWorkflowApprovalSupport(workflowId: "workflow-2", jobs: [makeWorkflowJob(type: "approval", status: "not_run")])

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
        appState.recordWorkflowApprovalSupport(workflowId: "workflow-1", jobs: [makeWorkflowJob(type: "approval", status: "not_run")])

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
                [
                    WorkflowJob(
                        id: "approval-job-1",
                        name: "Deploy approval",
                        projectSlug: "gh/org/repo",
                        status: "on_hold",
                        type: "approval",
                        approvedBy: nil,
                        startedAt: nil,
                        stoppedAt: nil,
                        jobNumber: nil
                    )
                ]
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
        appState.recordWorkflowApprovalSupport(workflowId: "workflow-1", jobs: [makeWorkflowJob(type: "approval", status: "not_run")])

        appState.armAutoApprove(for: makeBuild())
        await poller.checkNow()

        XCTAssertEqual(approvedRequests.count, 1)
        XCTAssertEqual(approvedRequests.first?.0, "workflow-1")
        XCTAssertEqual(approvedRequests.first?.1, "approval-job-1")
        XCTAssertEqual(sentNotifications.count, 1)
        XCTAssertEqual(sentNotifications.first?.0, "workflow-1")
        XCTAssertEqual(sentNotifications.first?.1, "Deploy approval")
        XCTAssertEqual(refreshed, 1)
        XCTAssertTrue(appState.armedAutoApprovals.isEmpty)
    }

    func testWorkflowClearsArmedApprovalAfterApprovalHasAlreadyBeenConsumed() async {
        var approvedRequests = 0

        let poller = AutoApprovalPoller(
            fetchWorkflowJobs: { _ in
                [
                    WorkflowJob(
                        id: "approval-job",
                        name: "Deploy approval",
                        projectSlug: "gh/org/repo",
                        status: "success",
                        type: "approval",
                        approvedBy: "user-123",
                        startedAt: nil,
                        stoppedAt: nil,
                        jobNumber: 10
                    ),
                    WorkflowJob(
                        id: "job-1",
                        name: "Deploy",
                        projectSlug: "gh/org/repo",
                        status: "running",
                        type: "deploy",
                        approvedBy: nil,
                        startedAt: nil,
                        stoppedAt: nil,
                        jobNumber: 11
                    )
                ]
            },
            approvePendingJob: { _, _ in
                approvedRequests += 1
            }
        )
        let appState = AppState(autoApprovalPoller: poller)
        appState.recordWorkflowApprovalSupport(workflowId: "workflow-1", jobs: [makeWorkflowJob(type: "approval", status: "not_run")])

        appState.armAutoApprove(for: makeBuild())
        await poller.checkNow()

        XCTAssertEqual(approvedRequests, 0)
        XCTAssertTrue(appState.armedAutoApprovals.isEmpty)
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
        appState.recordWorkflowApprovalSupport(workflowId: "workflow-1", jobs: [makeWorkflowJob(type: "approval", status: "not_run")])

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
            )
        )
    }

    private func makeWorkflowJob(type: String, status: String = "success") -> WorkflowJob {
        WorkflowJob(
            id: "\(type)-job",
            name: "\(type.capitalized) Job",
            projectSlug: "gh/org/repo",
            status: status,
            type: type,
            approvedBy: nil,
            startedAt: nil,
            stoppedAt: nil,
            jobNumber: 10
        )
    }
}
