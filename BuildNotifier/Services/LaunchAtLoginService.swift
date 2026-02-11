import Foundation
import ServiceManagement

// MARK: - Launch at Login Service

final class LaunchAtLoginService {
    static let shared = LaunchAtLoginService()
    
    private init() {}
    
    var isEnabled: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to \(newValue ? "enable" : "disable") launch at login: \(error)")
            }
        }
    }
}
