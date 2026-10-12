// LaunchAtLoginManager.swift
// Manages launch-at-login via a LaunchAgent plist in ~/Library/LaunchAgents/.
//
// WHY NOT SMAppService:
// SMAppService.mainApp is tied to the app's code signing identity. Ad-hoc
// re-signing on every deploy (deploy.sh) changes the identity, so macOS
// silently drops the login item registration after each update.
//
// A LaunchAgent plist references the app by PATH, not signature. It survives
// every binary update and re-sign without any re-registration needed.

import Foundation
import ServiceManagement

public enum LaunchAtLoginManager {

    private static let plistLabel   = "com.trackpadvolumeknob"
    private static let plistURL     = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/LaunchAgents/com.trackpadvolumeknob.plist")
    private static let appPath      = "/Applications/MacTrackpadFix.app/Contents/MacOS/MacTrackpadFix"

    public static func setEnabled(_ enabled: Bool) {
        if enabled {
            install()
        } else {
            remove()
        }
    }

    public static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    // MARK: - Private

    private static func install() {
        let launchAgentsDir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: launchAgentsDir,
                                                  withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": plistLabel,
            "ProgramArguments": [appPath],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false]
        ]

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                          format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)

            // Load it immediately so it takes effect without a reboot
            let result = Process.run("/bin/launchctl",
                                     arguments: ["load", plistURL.path])
            if result == 0 {
                Logger.info("LaunchAtLogin: installed and loaded.")
            } else {
                Logger.warning("LaunchAtLogin: installed plist but launchctl load returned \(result).")
            }
        } catch {
            Logger.error("LaunchAtLogin install failed: \(error.localizedDescription)")
        }
    }

    private static func remove() {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return }

        _ = Process.run("/bin/launchctl", arguments: ["unload", plistURL.path])

        do {
            try FileManager.default.removeItem(at: plistURL)
            Logger.info("LaunchAtLogin: removed.")
        } catch {
            Logger.error("LaunchAtLogin remove failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Process helper

private extension Process {
    @discardableResult
    static func run(_ launchPath: String, arguments: [String]) -> Int32 {
        let p = Process()
        p.launchPath = launchPath
        p.arguments = arguments
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
