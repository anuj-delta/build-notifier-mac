import XCTest
@testable import BuildNotifier

final class RowStatusTests: XCTestCase {
    func testTerminalWorkflowStatusesMap() {
        XCTAssertEqual(RowStatus(circleCIWorkflowStatus: "success"), .success)
        XCTAssertEqual(RowStatus(circleCIWorkflowStatus: "failed"), .failed)
        XCTAssertEqual(RowStatus(circleCIWorkflowStatus: "error"), .failed)
        XCTAssertEqual(RowStatus(circleCIWorkflowStatus: "unauthorized"), .failed)
        XCTAssertEqual(RowStatus(circleCIWorkflowStatus: "canceled"), .canceled)
    }

    func testInProgressAndHoldWorkflowStatusesMap() {
        XCTAssertEqual(RowStatus(circleCIWorkflowStatus: "running"), .running)
        XCTAssertEqual(RowStatus(circleCIWorkflowStatus: "failing"), .running)
        XCTAssertEqual(RowStatus(circleCIWorkflowStatus: "on_hold"), .onHold)
        XCTAssertEqual(RowStatus(circleCIWorkflowStatus: "not_run"), .neutral)
    }

    func testUnknownWorkflowStatusReturnsNilSoCallerFallsBack() {
        XCTAssertNil(RowStatus(circleCIWorkflowStatus: "made_up"))
        XCTAssertNil(RowStatus(circleCIWorkflowStatus: ""))
    }

    // The bug this fixes: v1.1 still reports the representative job as running while v2 has
    // rolled the workflow up to success. The v2 status must win so the row stops spinning.
    func testSuccessWorkflowStatusIsNotInProgress() {
        let success = try? XCTUnwrap(RowStatus(circleCIWorkflowStatus: "success"))
        XCTAssertEqual(success?.isInProgress, false)
    }
}
