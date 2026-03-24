import XCTest
@testable import BuildNotifier

@MainActor
final class BuildPollerTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "UserPreferences")
        super.tearDown()
    }

    func testPollMarksWorkflowAsApprovalCapableWhenApprovalJobExists() async {
        let build = makeBuild()
        let approvalJob = makeWorkflowJob(type: "approval", status: "on_hold")
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in
                [build]
            },
            fetchWorkflowJobs: { _ in
                [approvalJob]
            }
        )
        let appState = makeAppState(poller: poller)

        await poller.checkNow()

        XCTAssertEqual(appState.workflowApprovalSupport["workflow-1"], true)
        XCTAssertTrue(appState.canAutoApprove(build))
    }

    func testPollMarksWorkflowAsNotApprovalCapableWhenNoApprovalJobExists() async {
        let build = makeBuild()
        let workflowJob = makeWorkflowJob(type: "build")
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in
                [build]
            },
            fetchWorkflowJobs: { _ in
                [workflowJob]
            }
        )
        let appState = makeAppState(poller: poller)

        await poller.checkNow()

        XCTAssertEqual(appState.workflowApprovalSupport["workflow-1"], false)
        XCTAssertFalse(appState.canAutoApprove(build))
    }

    func testPollLeavesApprovalSupportUnknownOnTransientWorkflowJobError() async {
        enum TestError: Error {
            case network
        }

        let build = makeBuild()
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in
                [build]
            },
            fetchWorkflowJobs: { _ in
                throw TestError.network
            }
        )
        let appState = makeAppState(poller: poller)

        await poller.checkNow()

        XCTAssertNil(appState.workflowApprovalSupport["workflow-1"])
        XCTAssertFalse(appState.canAutoApprove(build))
    }

    private func makeAppState(poller: BuildPoller) -> AppState {
        let appState = AppState(poller: poller, autoApprovalPoller: AutoApprovalPoller())
        appState.preferences.watchedProjects = [makeWatchedProject()]
        return appState
    }

    private func makeWatchedProject() -> WatchedProject {
        WatchedProject(
            id: "gh/org/repo",
            vcsType: "gh",
            orgName: "org",
            repoName: "repo"
        )
    }

    private func makeBuild() -> Build {
        Build(
            vcsUrl: "https://github.com/org/repo",
            buildUrl: "https://app.circleci.com/pipelines/workflows/workflow-1",
            buildNum: 42,
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
                workflowId: "workflow-1",
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
