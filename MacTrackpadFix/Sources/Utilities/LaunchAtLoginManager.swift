// LaunchAtLoginManager.swift — SMAppService launch-at-login wrapper
import ServiceManagement
import Foundation

public enum LaunchAtLoginManager {

    public static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled { return }
                try SMAppService.mainApp.register()
                Logger.info("LaunchAtLogin: registered.")
            } else {
                if SMAppService.mainApp.status == .notRegistered { return }
                try SMAppService.mainApp.unregister()
                Logger.info("LaunchAtLogin: unregistered.")
            }
        } catch {
            Logger.error("LaunchAtLogin: \(error.localizedDescription)")
        }
    }

    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
