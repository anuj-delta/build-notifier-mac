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

    private let fetchWorkflowJobs: (String) async throws -> [WorkflowJob]
    private let approvePendingJob: (String, String) async throws -> Void
    private let sendAutoApprovedNotification: (ArmedAutoApproval, String, Bool) -> Void
    private let requestBuildRefresh: (AppState) -> Void
    private let now: () -> Date

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

    func startPolling(interval: TimeInterval = 120) {
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

    func poll() {
        pollTask?.cancel()
        pollTask = Task {
            await checkNow()
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

                if let pendingJob = jobs.first(where: { $0.isPendingApproval }) {
                    try await approvePendingJob(armedApproval.workflowId, pendingJob.id)

                    appState.armedAutoApprovals.removeValue(forKey: armedApproval.workflowId)
                    requestBuildRefresh(appState)

                    if appState.preferences.notificationsEnabled {
                        sendAutoApprovedNotification(
                            armedApproval,
                            pendingJob.name,
                            appState.preferences.notificationSoundEnabled
                        )
                    }
                    continue
                }

                if shouldClearArmedApproval(for: jobs) {
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

    private func shouldClearArmedApproval(for jobs: [WorkflowJob]) -> Bool {
        guard !jobs.isEmpty else { return false }

        if jobs.contains(where: \.canStillRequireApproval) {
            return false
        }

        return true
    }
}
