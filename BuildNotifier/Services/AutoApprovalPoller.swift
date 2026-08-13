import Foundation
import Combine

// MARK: - Auto Approval Poller

@MainActor
final class AutoApprovalPoller: ObservableObject {
    @Published private(set) var isPolling = false
    @Published private(set) var lastPollTime: Date?
    @Published private(set) var error: Error?

    private var scheduleTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    /// Gates already sent to CircleCI. A job keeps reporting `on_hold` for a few seconds
    /// after it is approved, so without this the next poll approves it again.
    private var approvedGateIds: Set<String> = []

    private let fetchWorkflowJobs: (String) async throws -> [WorkflowJob]
    private let approvePendingJob: (String, String) async throws -> Void
    private let sendAutoApprovedNotification: (ArmedAutoApproval, String, Bool) -> Void
    private let requestBuildRefresh: (AppState) -> Void
    private let now: () -> Date

    /// Approve responses that mean the gate is gone rather than that the request was bad.
    private static let gateRejectedCodes: Set<Int> = [400, 404, 409]

    weak var appState: AppState?

    init(
        fetchWorkflowJobs: ((String) async throws -> [WorkflowJob])? = nil,
        approvePendingJob: ((String, String) async throws -> Void)? = nil,
        sendAutoApprovedNotification: ((ArmedAutoApproval, String, Bool) -> Void)? = nil,
        requestBuildRefresh: ((AppState) -> Void)? = nil,
        now: (() -> Date)? = nil
    ) {
        self.fetchWorkflowJobs = fetchWorkflowJobs ?? { workflowId in
            try await CircleCIAPI.shared.getWorkflowJobs(workflowId: workflowId)
        }
        self.approvePendingJob = approvePendingJob ?? { workflowId, approvalRequestId in
            try await CircleCIAPI.shared.approveJob(
                workflowId: workflowId,
                approvalRequestId: approvalRequestId
            )
        }
        self.sendAutoApprovedNotification = sendAutoApprovedNotification ?? { armedApproval, jobName, soundEnabled in
            NotificationManager.shared.sendAutoApprovedNotification(
                armedApproval: armedApproval,
                jobName: jobName,
                soundEnabled: soundEnabled
            )
        }
        self.requestBuildRefresh = requestBuildRefresh ?? { appState in
            appState.poller.poll()
        }
        self.now = now ?? Date.init
    }

    // MARK: - Start/Stop Polling

    func startPolling(interval: TimeInterval = 30) {
        stopPolling()

        isPolling = true
        poll()

        scheduleTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                self.poll()
            }
        }
    }

    func stopPolling() {
        scheduleTask?.cancel()
        scheduleTask = nil
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }

    /// Polls run one after another. Cancelling a poll in flight could drop an approval
    /// between the fetch and the POST, so a new poll waits for the current one.
    func poll() {
        let running = pollTask
        pollTask = Task { @MainActor in
            _ = await running?.value
            guard !Task.isCancelled else { return }
            await self.checkNow()
        }
    }

    func checkNow() async {
        await performPoll()
    }

    // MARK: - Poll Implementation

    private func performPoll() async {
        guard let appState = appState else { return }

        let armedApprovals = Array(appState.armedAutoApprovals.values)
        guard !armedApprovals.isEmpty else {
            approvedGateIds.removeAll()
            lastPollTime = now()
            error = nil
            return
        }

        error = nil

        for armedApproval in armedApprovals {
            if Task.isCancelled {
                return
            }

            do {
                let jobs = try await fetchWorkflowJobs(armedApproval.workflowId)

                var approved = false
                for gate in jobs where gate.isPendingApproval && !approvedGateIds.contains(gate.id) {
                    if try await approve(gate, for: armedApproval, appState: appState) {
                        approved = true
                    }
                }
                if approved {
                    requestBuildRefresh(appState)
                }

                // A workflow can hold more than one gate, so stay armed until it is done.
                if !jobs.isEmpty, !jobs.contains(where: \.isActive) {
                    appState.armedAutoApprovals.removeValue(forKey: armedApproval.workflowId)
                }
            } catch is CancellationError {
                return
            } catch {
                self.error = error
            }
        }

        lastPollTime = now()
    }

    /// Approves one gate and reports whether CircleCI accepted it.
    private func approve(
        _ gate: WorkflowJob,
        for armedApproval: ArmedAutoApproval,
        appState: AppState
    ) async throws -> Bool {
        do {
            try await approvePendingJob(armedApproval.workflowId, gate.id)
            approvedGateIds.insert(gate.id)
        } catch CircleCIError.httpError(let code, _) where Self.gateRejectedCodes.contains(code) {
            approvedGateIds.insert(gate.id)
            return false
        }

        if appState.preferences.notificationsEnabled {
            sendAutoApprovedNotification(
                armedApproval,
                gate.name,
                appState.preferences.notificationSoundEnabled
            )
        }
        return true
    }
}
