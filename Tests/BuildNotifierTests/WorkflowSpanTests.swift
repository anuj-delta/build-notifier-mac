import XCTest
@testable import BuildNotifier

final class WorkflowSpanTests: XCTestCase {
    // The bug this fixes: the row read "1m ago" for a deploy that ran for 12 minutes,
    // because it took the timestamp off the newest job instead of the whole workflow.
    func testRunningWorkflowCountsFromTheEarliestJobStart() {
        let span = WorkflowSpan(jobs: [
            job(startedMinutesAgo: 12, stoppedMinutesAgo: 9, status: "success"),
            job(startedMinutesAgo: 1, stoppedMinutesAgo: nil, status: "running")
        ])

        XCTAssertEqual(span.label(inProgress: true), "running 12m")
    }

    func testFinishedWorkflowCountsFromTheLatestJobStop() {
        let span = WorkflowSpan(jobs: [
            job(startedMinutesAgo: 12, stoppedMinutesAgo: 9, status: "success"),
            job(startedMinutesAgo: 9, stoppedMinutesAgo: 1, status: "success")
        ])

        XCTAssertEqual(span.label(inProgress: false), "1m ago")
    }

    func testWorkflowWithAJobStillGoingHasNoStopTime() {
        let span = WorkflowSpan(jobs: [
            job(startedMinutesAgo: 12, stoppedMinutesAgo: 9, status: "success"),
            job(startedMinutesAgo: 9, stoppedMinutesAgo: nil, status: "running")
        ])

        XCTAssertNil(span.stopped)
        XCTAssertEqual(span.label(inProgress: false), "12m ago")
    }

    func testWorkflowThatHasNotStartedReadsAsQueued() {
        let span = WorkflowSpan(jobs: [job(startedMinutesAgo: nil, stoppedMinutesAgo: nil, status: "queued")])

        XCTAssertEqual(span.label(inProgress: true), "queued")
    }

    private func job(startedMinutesAgo: Int?, stoppedMinutesAgo: Int?, status: String) -> Build {
        Build(
            vcsUrl: "https://github.com/delta-exchange/support-chatbot",
            buildUrl: nil,
            buildNum: 1,
            branch: "develop",
            vcsRevision: nil,
            committerName: nil,
            committerEmail: nil,
            authorName: nil,
            authorEmail: nil,
            subject: nil,
            body: nil,
            why: "github",
            queuedAt: nil,
            startTime: startedMinutesAgo.map(Self.iso),
            stopTime: stoppedMinutesAgo.map(Self.iso),
            buildTimeMillis: nil,
            username: "delta-exchange",
            reponame: "support-chatbot",
            lifecycle: status == "success" ? "finished" : "running",
            outcome: status == "success" ? "success" : nil,
            status: status,
            retryOf: nil,
            workflows: WorkflowInfo(jobName: "job", workflowId: "wf-1", workflowName: "build-and-deploy"),
            pullRequests: nil
        )
    }

    private static func iso(minutesAgo: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date().addingTimeInterval(-Double(minutesAgo) * 60))
    }
}
