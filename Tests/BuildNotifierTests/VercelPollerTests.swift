import XCTest
@testable import BuildNotifier

@MainActor
final class VercelPollerTests: XCTestCase {
    func testFailedFirstSnapshotDoesNotReplayExistingDeploymentAfterRecovery() async {
        enum TestError: Error { case unavailable }

        var shouldFailFetch = true
        var deployments = [makeDeployment(uid: "existing", state: "READY")]
        var readyNotifications: [VercelDeployment] = []
        let poller = VercelPoller(
            fetchDeployments: { _, _, _ in
                if shouldFailFetch { throw TestError.unavailable }
                return deployments
            },
            sendDeploymentReadyNotification: { deployment, _ in
                readyNotifications.append(deployment)
            }
        )
        let appState = AppState(
            poller: BuildPoller(),
            vercelPoller: poller,
            autoApprovalPoller: AutoApprovalPoller()
        )
        appState.preferences.watchedVercelProjects = [
            WatchedVercelProject(id: "project-1", teamId: nil, projectName: "web")
        ]
        appState.preferences.vercelNotificationsEnabled = true
        appState.preferences.notifyOnDeploymentReady = true
        appState.preferences.celebrateProdSuccess = false
        appState.preferences.playFailureSound = false

        await poller.checkNow()
        shouldFailFetch = false
        await poller.checkNow()

        XCTAssertTrue(readyNotifications.isEmpty)

        deployments.insert(makeDeployment(uid: "new", state: "READY"), at: 0)
        await poller.checkNow()

        XCTAssertNotNil(appState.deploymentsByProject["project-1"])
        XCTAssertEqual(readyNotifications.map(\.uid), ["new"])
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
}
