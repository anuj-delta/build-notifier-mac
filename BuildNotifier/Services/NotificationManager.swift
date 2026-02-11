import Foundation
import UserNotifications
import AppKit

// MARK: - Notification Manager

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published private(set) var isAuthorized = false
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            isAuthorized = granted
        } catch {
            print("Notification authorization error: \(error)")
            isAuthorized = false
        }
    }
    
    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }
    
    // MARK: - Send Notifications
    
    func sendBuildSuccessNotification(build: Build, soundEnabled: Bool = true) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Build Passed"
        content.subtitle = "\(build.projectSlug) (\(build.branch ?? "unknown"))"
        content.body = build.truncatedSubject
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
        content.title = "Build Failed"
        content.subtitle = "\(build.projectSlug) (\(build.branch ?? "unknown"))"
        content.body = build.truncatedSubject
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
        content.title = "Approval Required"
        content.subtitle = "\(approval.build.projectSlug) (\(approval.build.branch ?? "unknown"))"
        content.body = "\(approval.jobName) waiting for approval"
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
    
    func sendBuildStartedNotification(build: Build, soundEnabled: Bool = true) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Build Started"
        content.subtitle = "\(build.projectSlug) (\(build.branch ?? "unknown"))"
        content.body = build.truncatedSubject
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
        content.title = "Deployment Ready"
        content.subtitle = "\(deployment.projectName) (\(deployment.meta?.branch ?? "unknown"))"
        content.body = deployment.truncatedCommitMessage
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
        content.title = "Deployment Failed"
        content.subtitle = "\(deployment.projectName) (\(deployment.meta?.branch ?? "unknown"))"
        content.body = deployment.truncatedCommitMessage
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
            // Always check/request authorization first
            if !isAuthorized {
                await requestAuthorization()
            }
            
            // Check again after requesting
            await checkAuthorizationStatus()
            
            guard isAuthorized else {
                print("Notifications not authorized - please enable in System Settings")
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = "Test Notification"
            content.subtitle = "CircleCI Notifier"
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
