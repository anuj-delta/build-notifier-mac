import XCTest
@testable import BuildNotifier

@MainActor
final class PostTriggerRefreshTests: XCTestCase {
    func testSchedulesImmediatePollPlusOnePerDelay() async throws {
        var fetchCount = 0
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in
                fetchCount += 1
                return []
            }
        )
        let appState = AppState(poller: poller)
        appState.preferences.watchedProjects = [
            WatchedProject(
                id: "gh/delta-exchange/api-console",
                vcsType: "gh",
                orgName: "delta-exchange",
                repoName: "api-console",
                followMode: .all,
                isEnabled: true
            )
        ]
        appState.postTriggerRefreshDelays = [0.02, 0.02, 0.02]

        appState.schedulePostTriggerRefresh()

        try await Task.sleep(nanoseconds: 500_000_000)

        // 1 immediate poll + 1 checkNow per delay, one watched project each.
        XCTAssertEqual(fetchCount, 4)
    }

    func testNoDelaysStillPollsOnce() async throws {
        var fetchCount = 0
        let poller = BuildPoller(
            fetchBuilds: { _, _, _, _ in
                fetchCount += 1
                return []
            }
        )
        let appState = AppState(poller: poller)
        appState.preferences.watchedProjects = [
            WatchedProject(
                id: "gh/delta-exchange/api-console",
                vcsType: "gh",
                orgName: "delta-exchange",
                repoName: "api-console",
                followMode: .all,
                isEnabled: true
            )
        ]
        appState.postTriggerRefreshDelays = []

        appState.schedulePostTriggerRefresh()

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(fetchCount, 1)
    }
}
