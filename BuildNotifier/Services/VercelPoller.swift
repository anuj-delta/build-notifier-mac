import Foundation
import Combine

// MARK: - Vercel Poller

@MainActor
final class VercelPoller: ObservableObject {
    @Published private(set) var isPolling = false
    @Published private(set) var lastPollTime: Date?
    @Published private(set) var error: Error?
    
    private var scheduleTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var hasEstablishedBaseline = false
    
    weak var appState: AppState?
    
    init() {}
    
    // MARK: - Start/Stop Polling
    
    func startPolling(interval: TimeInterval = 60) {
        stopPolling()

        isPolling = true
        hasEstablishedBaseline = false

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
        hasEstablishedBaseline = false
    }
    
    func poll() {
        pollTask?.cancel()
        pollTask = Task {
            await performPoll()
        }
    }
    
    // MARK: - Poll Implementation
    
    private func performPoll() async {
        guard let appState = appState else { return }
        
        let watchedProjects = appState.preferences.watchedVercelProjects.filter { $0.isEnabled }
        guard !watchedProjects.isEmpty else {
            lastPollTime = Date()
            return
        }
        
        error = nil
        
        let previousDeployments = appState.deploymentsByProject
        let currentVercelUser = appState.vercelUser
        
        var newDeploymentsByProject: [String: [VercelDeployment]] = [:]
        
        await withTaskGroup(of: (String, [VercelDeployment])?.self) { group in
            for project in watchedProjects {
                group.addTask {
                    do {
                        let deployments = try await VercelAPI.shared.getDeployments(
                            projectId: project.id,
                            teamId: project.teamId,
                            limit: 20
                        )
                        let filteredDeployments: [VercelDeployment]
                        if project.followMode == .mine {
                            filteredDeployments = deployments.filter { deployment in
                                deployment.belongsToCurrentUser(currentVercelUser)
                            }
                        } else {
                            filteredDeployments = deployments
                        }
                        return (project.id, filteredDeployments)
                    } catch {
                        return nil
                    }
                }
            }
            
            for await result in group {
                if let (projectId, deployments) = result {
                    newDeploymentsByProject[projectId] = deployments
                }
            }
        }
        
        appState.deploymentsByProject = newDeploymentsByProject
        lastPollTime = Date()

        if !hasEstablishedBaseline {
            establishNotificationBaseline(current: newDeploymentsByProject)
            hasEstablishedBaseline = true
            return
        }

        await checkForStatusChanges(
            previous: previousDeployments,
            current: newDeploymentsByProject,
            preferences: appState.preferences
        )
    }
    
    // MARK: - Status Change Detection
    
    private func checkForStatusChanges(
        previous: [String: [VercelDeployment]],
        current: [String: [VercelDeployment]],
        preferences: UserPreferences
    ) async {
        guard let appState = appState else { return }

        // Celebrations gate only on their own prefs, independent of Vercel notifications.
        let vercelNotificationsEnabled = preferences.vercelNotificationsEnabled
        let celebrationsWanted = preferences.celebrateProdSuccess || preferences.playFailureSound
        guard vercelNotificationsEnabled || celebrationsWanted else { return }

        let notificationManager = NotificationManager.shared
        let soundEnabled = preferences.notificationSoundEnabled

        var newNotifiedDeployments = appState.notifiedVercelDeployments
        var newCelebratedDeployments = appState.celebratedVercelDeployments
        var newPlayedFailureDeployments = appState.playedFailureVercelDeployments

        for (projectId, currentDeployments) in current {
            let previousDeployments = previous[projectId] ?? []

            for deployment in currentDeployments {
                let previousDeployment = previousDeployments.first { $0.uid == deployment.uid }
                let previousStatus = previousDeployment?.deploymentStatus
                let currentStatus = deployment.deploymentStatus
                let isNewOrChanged = previousStatus != currentStatus || previousDeployment == nil

                // Notifications (unchanged behavior; keyed by uid+status)
                let notificationKey = "\(deployment.uid)-\(currentStatus.rawValue)"
                if vercelNotificationsEnabled, isNewOrChanged,
                   !newNotifiedDeployments.contains(notificationKey) {
                    if currentStatus.isSuccess && preferences.notifyOnDeploymentReady {
                        notificationManager.sendDeploymentReadyNotification(deployment: deployment, soundEnabled: soundEnabled)
                        newNotifiedDeployments.insert(notificationKey)
                    } else if currentStatus.isFailure && preferences.notifyOnDeploymentError {
                        notificationManager.sendDeploymentErrorNotification(deployment: deployment, soundEnabled: soundEnabled)
                        newNotifiedDeployments.insert(notificationKey)
                    }
                }

                // Celebrations (own uid-keyed dedup, seeded at baseline)
                if currentStatus.isSuccess, deployment.isProduction,
                   preferences.celebrateProdSuccess,
                   !newCelebratedDeployments.contains(deployment.uid) {
                    appState.celebrateProdSuccess(projectLabel: deployment.projectName)
                    newCelebratedDeployments.insert(deployment.uid)
                }
                if currentStatus.isFailure, preferences.playFailureSound,
                   !newPlayedFailureDeployments.contains(deployment.uid) {
                    appState.playFailureSound()
                    newPlayedFailureDeployments.insert(deployment.uid)
                }
            }
        }

        appState.notifiedVercelDeployments = newNotifiedDeployments
        appState.celebratedVercelDeployments = newCelebratedDeployments
        appState.playedFailureVercelDeployments = newPlayedFailureDeployments
    }

    private func establishNotificationBaseline(current: [String: [VercelDeployment]]) {
        guard let appState = appState else { return }

        var baselineKeys = Set<String>()
        var celebratedBaseline = Set<String>()
        var failureBaseline = Set<String>()
        for (_, deployments) in current {
            for deployment in deployments {
                let status = deployment.deploymentStatus
                guard status.isSuccess || status.isFailure else { continue }
                baselineKeys.insert("\(deployment.uid)-\(status.rawValue)")
                if status.isSuccess { celebratedBaseline.insert(deployment.uid) }
                if status.isFailure { failureBaseline.insert(deployment.uid) }
            }
        }

        appState.notifiedVercelDeployments = baselineKeys
        appState.celebratedVercelDeployments = celebratedBaseline
        appState.playedFailureVercelDeployments = failureBaseline
    }
}

private extension VercelDeployment {
    func belongsToCurrentUser(_ user: VercelUserInfo?) -> Bool {
        guard let user else { return false }

        let userIdentifiers = Set(
            [user.id, user.email, user.name, user.username]
                .compactMap(Self.normalizedIdentifier)
        )

        guard !userIdentifiers.isEmpty else { return false }

        let deploymentIdentifiers = Set(
            [
                creator?.uid,
                creator?.email,
                creator?.username,
                meta?.authorName,
                meta?.authorLogin
            ]
            .compactMap(Self.normalizedIdentifier)
        )

        return !deploymentIdentifiers.isDisjoint(with: userIdentifiers)
    }

    static func normalizedIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}
