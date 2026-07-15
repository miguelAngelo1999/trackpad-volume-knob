// PermissionsManager.swift
// Checks and requests the Accessibility permission required by TrackpadVolumeKnob.
import AppKit
import ApplicationServices

public enum PermissionsManager {

    /// Returns true if the Accessibility permission has been granted.
    public static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility access.
    @discardableResult
    public static func requestAccessibilityPermission(showPrompt: Bool = true) -> Bool {
        // Use the stable string constant value to avoid Swift 6 concurrency
        // warnings on the C global kAXTrustedCheckOptionPrompt.
        let key = "AXTrustedCheckOptionPrompt"
        let options: NSDictionary = [key: showPrompt]
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Settings › Privacy & Security › Accessibility.
    public static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
