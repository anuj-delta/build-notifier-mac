import XCTest
@testable import BuildNotifierCore

final class CircleCIMCPServiceTests: XCTestCase {
    func testWatchedProjectSlugLoaderReadsSavedPreferences() throws {
        let suiteName = "CircleCIMCPServiceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create test defaults suite")
            return
        }

        let json = """
        {
          "watchedProjects": [
            { "orgName": "delta-exchange", "repoName": "api-console" },
            { "id": "gh/build-notifier/example" }
          ]
        }
        """
        defaults.set(Data(json.utf8), forKey: "UserPreferences")

        let watchedSlugs = CircleCIMCPService.loadWatchedProjectSlugs(userDefaults: defaults)
        XCTAssertEqual(watchedSlugs, ["delta-exchange/api-console", "build-notifier/example"])
    }

    func testProjectActivitySortingPrefersMostRecentThenName() {
        let summaries = [
            ProjectActivitySummary(
                projectSlug: "b/repo",
                displayName: "b/repo",
                vcsUrl: nil,
                watched: false,
                latestBuildNum: 2,
                latestBranch: "main",
                latestStatus: "success",
                latestActivityAt: "2026-04-14T09:00:00Z",
                latestSubject: nil,
                buildUrl: nil,
                workflowId: nil
            ),
            ProjectActivitySummary(
                projectSlug: "a/repo",
                displayName: "a/repo",
                vcsUrl: nil,
                watched: false,
                latestBuildNum: 1,
                latestBranch: "main",
                latestStatus: "success",
                latestActivityAt: "2026-04-14T09:00:00Z",
                latestSubject: nil,
                buildUrl: nil,
                workflowId: nil
            ),
            ProjectActivitySummary(
                projectSlug: "c/repo",
                displayName: "c/repo",
                vcsUrl: nil,
                watched: false,
                latestBuildNum: nil,
                latestBranch: nil,
                latestStatus: nil,
                latestActivityAt: nil,
                latestSubject: nil,
                buildUrl: nil,
                workflowId: nil
            )
        ]

        let sorted = summaries.sorted(by: CircleCIMCPService.compareProjectActivity)
        XCTAssertEqual(sorted.map(\.projectSlug), ["a/repo", "b/repo", "c/repo"])
    }

    func testErrorDescriptionsAreActionable() {
        XCTAssertEqual(
            CircleCIMCPServiceError.authRequired.errorDescription,
            "No saved CircleCI login found. Open Build Notifier and sign in first."
        )
        XCTAssertEqual(
            CircleCIMCPServiceError.buildNotFound(projectSlug: "delta/repo", buildNumber: 42).errorDescription,
            "Build #42 was not found for delta/repo."
        )
    }
}
