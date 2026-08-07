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
            },
            now: { Self.justAfterFixtures }
        )
        let appState = makeAppState(poller: poller)

        await poller.checkNow()
        shouldFailFetch = false
        await poller.checkNow()

        XCTAssertTrue(readyNotifications.isEmpty)

        deployments.insert(makeDeployment(uid: "new", state: "READY"), at: 0)
        await poller.checkNow()

        XCTAssertNotNil(appState.deploymentsByProject["project-1"])
        XCTAssertEqual(readyNotifications.map(\.uid), ["new"])
    }

    func testStaleUnseenDeploymentIsNotAnnouncedButIsStillMarkedNotified() async {
        var deployments = [makeDeployment(uid: "existing", state: "READY")]
        var readyNotifications: [VercelDeployment] = []
        let poller = VercelPoller(
            fetchDeployments: { _, _, _ in deployments },
            sendDeploymentReadyNotification: { deployment, _ in
                readyNotifications.append(deployment)
            },
            now: { Self.longAfterFixtures }
        )
        let appState = makeAppState(poller: poller)

        await poller.checkNow()
        deployments.insert(makeDeployment(uid: "new", state: "READY"), at: 0)
        await poller.checkNow()

        XCTAssertTrue(readyNotifications.isEmpty)
        XCTAssertTrue(appState.notifiedVercelDeployments.contains("new-READY"))
    }

    func testObservedFailureIsAnnouncedEvenWhenTheDeploymentIsOld() async {
        var deployments = [makeDeployment(uid: "existing", state: "BUILDING")]
        var errorNotifications: [VercelDeployment] = []
        let poller = VercelPoller(
            fetchDeployments: { _, _, _ in deployments },
            sendDeploymentErrorNotification: { deployment, _ in
                errorNotifications.append(deployment)
            },
            now: { Self.longAfterFixtures }
        )
        let appState = makeAppState(poller: poller)

        await poller.checkNow()
        deployments = [makeDeployment(uid: "existing", state: "ERROR")]
        await poller.checkNow()

        XCTAssertEqual(errorNotifications.map(\.uid), ["existing"])
        XCTAssertTrue(appState.notifiedVercelDeployments.contains("existing-ERROR"))
    }

    /// The fixtures use a fixed creation time, so pin the clock just after it to keep
    /// them inside the freshness window.
    private static let justAfterFixtures = Date(timeIntervalSince1970: 1_700_000_060)
    private static let longAfterFixtures = Date(timeIntervalSince1970: 1_700_007_200)

    private func makeAppState(poller: VercelPoller) -> AppState {
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
        appState.preferences.notifyOnDeploymentError = true
        appState.preferences.celebrateProdSuccess = false
        appState.preferences.playFailureSound = false
        return appState
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
