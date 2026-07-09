import Foundation
import UserNotifications
import AppKit

// MARK: - Notification Manager

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    // Held for the app's lifetime; the singleton is never deallocated.
    private var activationObserver: NSObjectProtocol?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self

        // Refresh when a Build Notifier window gains focus (e.g. returning from
        // System Settings). Popover-only usage doesn't activate an .accessory
        // app, so AppState.refreshNow() also refreshes on popover open.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.checkAuthorizationStatus()
            }
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
        } catch {
            print("Notification authorization error: \(error)")
        }
        await checkAuthorizationStatus()
    }

    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if authorizationStatus != settings.authorizationStatus {
            authorizationStatus = settings.authorizationStatus
        }
    }

    /// Opens System Settings > Notifications, deep-linked to this app when possible.
    func openSystemNotificationSettings() {
        let pane = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"

        if let bundleId = Bundle.main.bundleIdentifier,
           let deepLink = URL(string: "\(pane)?id=\(bundleId)"),
           NSWorkspace.shared.open(deepLink) {
            return
        }
        if let paneURL = URL(string: pane), NSWorkspace.shared.open(paneURL) {
            return
        }
        // The pane identifier is not public API; fall back to the app itself.
        if let settingsApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.open(settingsApp)
        }
    }
    
    // MARK: - Send Notifications

    /// Appends the commit/PR author to a message body, e.g. "Ship it · by anuj-sharma".
    private func withAuthor(_ message: String, author: String?) -> String {
        guard let author, !author.isEmpty else { return message }
        return "\(message) · by \(author)"
    }

    func sendBuildSuccessNotification(build: Build, soundEnabled: Bool = true) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "✅ Build passed"
        content.subtitle = "\(build.projectSlug) (\(build.branch ?? "unknown"))"
        content.body = withAuthor(build.truncatedSubject, author: build.authorDisplayName)
        content.sound = soundEnabled ? .default : nil
        content.userInfo = [
            "buildUrl": build.workflowUrl ?? build.buildUrl ?? "",
            "type": "success"
        ]
        
        let request = UNNotificationRequest(
            identifier: "build-success-\(build.id)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func sendBuildFailureNotification(build: Build, soundEnabled: Bool = true) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "❌ Build failed"
        content.subtitle = "\(build.projectSlug) (\(build.branch ?? "unknown"))"
        content.body = withAuthor(build.truncatedSubject, author: build.authorDisplayName)
        content.sound = soundEnabled ? .default : nil
        content.userInfo = [
            "buildUrl": build.workflowUrl ?? build.buildUrl ?? "",
            "type": "failure"
        ]
        
        let request = UNNotificationRequest(
            identifier: "build-failure-\(build.id)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func sendPendingApprovalNotification(approval: PendingApproval, soundEnabled: Bool = true) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "⏸️ Approval required"
        content.subtitle = "\(approval.build.projectSlug) (\(approval.build.branch ?? "unknown"))"
        content.body = withAuthor("\(approval.jobName) waiting for approval", author: approval.build.authorDisplayName)
        content.sound = soundEnabled ? .default : nil
        content.categoryIdentifier = "APPROVAL_CATEGORY"
        content.userInfo = [
            "buildUrl": approval.build.workflowUrl ?? approval.build.buildUrl ?? "",
            "workflowId": approval.workflowId,
            "jobId": approval.jobId,
            "type": "approval"
        ]
        
        let request = UNNotificationRequest(
            identifier: "approval-\(approval.id)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }

    func sendAutoApprovedNotification(
        armedApproval: ArmedAutoApproval,
        jobName: String,
        soundEnabled: Bool = true
    ) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "🤖 Auto-approved"
        content.subtitle = "\(armedApproval.projectSlug) (\(armedApproval.branch ?? "unknown"))"
        content.body = withAuthor("\(jobName) approved automatically", author: armedApproval.author)
        content.sound = soundEnabled ? .default : nil
        content.userInfo = [
            "buildUrl": armedApproval.buildUrl ?? "",
            "workflowId": armedApproval.workflowId,
            "type": "auto_approved"
        ]

        let request = UNNotificationRequest(
            identifier: "auto-approved-\(armedApproval.workflowId)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
    
    func sendBuildStartedNotification(build: Build, soundEnabled: Bool = true) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "🔄 Build started"
        content.subtitle = "\(build.projectSlug) (\(build.branch ?? "unknown"))"
        content.body = withAuthor(build.truncatedSubject, author: build.authorDisplayName)
        content.sound = soundEnabled ? .default : nil
        content.userInfo = [
            "buildUrl": build.workflowUrl ?? build.buildUrl ?? "",
            "type": "started"
        ]
        
        let request = UNNotificationRequest(
            identifier: "build-started-\(build.id)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Vercel Deployment Notifications
    
    func sendDeploymentReadyNotification(deployment: VercelDeployment, soundEnabled: Bool = true) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "✅ Deployment ready"
        content.subtitle = "\(deployment.projectName) (\(deployment.meta?.branch ?? "unknown"))"
        content.body = withAuthor(deployment.truncatedCommitMessage, author: deployment.authorDisplayName)
        content.sound = soundEnabled ? .default : nil
        content.userInfo = [
            "deploymentUrl": deployment.deploymentUrl ?? deployment.vercelDashboardUrl,
            "type": "deployment_ready"
        ]
        
        let request = UNNotificationRequest(
            identifier: "deployment-ready-\(deployment.uid)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func sendDeploymentErrorNotification(deployment: VercelDeployment, soundEnabled: Bool = true) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "❌ Deployment failed"
        content.subtitle = "\(deployment.projectName) (\(deployment.meta?.branch ?? "unknown"))"
        content.body = withAuthor(deployment.truncatedCommitMessage, author: deployment.authorDisplayName)
        content.sound = soundEnabled ? .default : nil
        content.userInfo = [
            "deploymentUrl": deployment.vercelDashboardUrl,
            "type": "deployment_error"
        ]
        
        let request = UNNotificationRequest(
            identifier: "deployment-error-\(deployment.uid)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func sendTestNotification() {
        Task {
            // The test exists to verify delivery, so never trust cached state.
            await checkAuthorizationStatus()
            if !isAuthorized {
                await requestAuthorization()
            }

            guard isAuthorized else {
                print("Notifications not authorized - please enable in System Settings")
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = "Test Notification"
            content.subtitle = "Build Notifier"
            content.body = "Notifications are working correctly!"
            content.sound = .default
            content.userInfo = ["type": "test"]
            
            let request = UNNotificationRequest(
                identifier: "test-\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            
            do {
                try await UNUserNotificationCenter.current().add(request)
                print("Test notification sent successfully")
            } catch {
                print("Failed to send test notification: \(error)")
            }
        }
    }
    
    // MARK: - Setup Notification Categories
    
    func setupNotificationCategories() {
        let approveAction = UNNotificationAction(
            identifier: "APPROVE_ACTION",
            title: "Approve",
            options: [.foreground]
        )
        
        let openAction = UNNotificationAction(
            identifier: "OPEN_ACTION",
            title: "Open in Browser",
            options: [.foreground]
        )
        
        let approvalCategory = UNNotificationCategory(
            identifier: "APPROVAL_CATEGORY",
            actions: [approveAction, openAction],
            intentIdentifiers: [],
            options: []
        )
        
        let buildCategory = UNNotificationCategory(
            identifier: "BUILD_CATEGORY",
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([
            approvalCategory,
            buildCategory
        ])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        
        switch response.actionIdentifier {
        case "APPROVE_ACTION":
            if let workflowId = userInfo["workflowId"] as? String,
               let jobId = userInfo["jobId"] as? String {
                Task {
                    try? await CircleCIAPI.shared.approveJob(
                        workflowId: workflowId,
                        approvalRequestId: jobId
                    )
                }
            }
            
        case "OPEN_ACTION", UNNotificationDefaultActionIdentifier:
            var urlString: String?
            if let buildUrl = userInfo["buildUrl"] as? String, !buildUrl.isEmpty {
                urlString = buildUrl
            } else if let deploymentUrl = userInfo["deploymentUrl"] as? String, !deploymentUrl.isEmpty {
                urlString = deploymentUrl
            }
            
            if let urlString = urlString, let url = URL(string: urlString) {
                _ = await MainActor.run {
                    NSWorkspace.shared.open(url)
                }
            }
            
        default:
            break
        }
    }
}
