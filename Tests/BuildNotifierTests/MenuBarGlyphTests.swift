import XCTest
@testable import BuildNotifier

@MainActor
final class MenuBarGlyphTests: XCTestCase {
    func testSpinnerReusesOneImagePerFrame() {
        let step = 1.0 / Double(MenuBarGlyph.spinnerFrames)
        for style in MenuBarDeployStyle.allCases {
            let first = MenuBarGlyph.deploying(style: style, phase: step)
            XCTAssertTrue(first === MenuBarGlyph.deploying(style: style, phase: step * 1.2))
            XCTAssertFalse(first === MenuBarGlyph.deploying(style: style, phase: step * 2))
            XCTAssertTrue(MenuBarGlyph.deploying(style: style, phase: 0) === MenuBarGlyph.deploying(style: style, phase: 1))
        }
    }

    func testBuildActivityFollowsBuildsAndReset() {
        let appState = AppState()
        XCTAssertFalse(appState.hasActiveBuildActivity)

        appState.buildsByProject = ["org/repo": [makeBuild()]]
        XCTAssertTrue(appState.hasActiveBuildActivity)

        appState.buildsByProject = [:]
        XCTAssertFalse(appState.hasActiveBuildActivity)
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
