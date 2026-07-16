// PermissionsManager.swift
// Checks and requests the Accessibility permission required by Mac Trackpad Fix.
import AppKit
import ApplicationServices

public enum PermissionsManager {

    private static let bundleID = "com.trackpadvolumeknob"

    /// Returns true if the Accessibility permission has been granted.
    public static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility access.
    @discardableResult
    public static func requestAccessibilityPermission(showPrompt: Bool = true) -> Bool {
        let key = "AXTrustedCheckOptionPrompt"
        let options: NSDictionary = [key: showPrompt]
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Remove the stale TCC entry so macOS will re-evaluate trust for the
    /// current binary. Must be called before opening System Settings —
    /// otherwise the existing (now-invalid) entry just stays checked.
    public static func resetAccessibilityTrust() {
        let task = Process()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", "Accessibility", bundleID]
        try? task.run()
        task.waitUntilExit()
    }

    /// Open System Settings › Privacy & Security › Accessibility.
    public static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Reset stale TCC entry then open System Settings so the user can
    /// re-enable the toggle. Returns immediately — caller should poll
    /// hasAccessibilityPermission() until it returns true.
    public static func resetAndRequestPermission() {
        resetAccessibilityTrust()
        // Small delay so tccutil finishes before Settings opens
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            openAccessibilitySettings()
        }
    }
}
