// AppDelegate.swift
// Root coordinator: owns the menu bar item, gesture pipeline, and window lifecycle.
import AppKit
import SwiftUI
import TrackpadVolumeKnobCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Owned objects
    private var statusItem: NSStatusItem?
    private var gestureEngine: GestureEngine?
    private var gestureInterpreter: GestureInterpreter?
    private var volumeController: VolumeController?
    private var hudController: HUDController?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    // MARK: - App lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the Dock icon — pure menu bar app
        NSApp.setActivationPolicy(.accessory)

        // Build the dependency graph
        let appSettings = AppSettings.shared
        let vol = VolumeController()
        volumeController = vol

        let hud = HUDController()
        hudController = hud

        let interpreter = GestureInterpreter(
            settings: appSettings,
            volumeController: vol,
            brightnessController: BrightnessController.shared,
            hudController: hud
        )
        gestureInterpreter = interpreter

        gestureEngine = GestureEngine(
            settings: appSettings,
            interpreter: interpreter
        )

        setupStatusItem()

        if !PermissionsManager.hasAccessibilityPermission() {
            showOnboarding()
        } else {
            gestureEngine?.start()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        gestureEngine?.stop()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "speaker.wave.2.circle",
                accessibilityDescription: "TrackpadVolumeKnob"
            )
            button.target = self
        }

        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: "TrackpadVolumeKnob", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let permItem = NSMenuItem(
            title: "Re-check Permissions",
            action: #selector(recheckPermissions),
            keyEquivalent: ""
        )
        permItem.target = self
        menu.addItem(permItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit TrackpadVolumeKnob",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Windows

    @objc func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.setContentSize(NSSize(width: 460, height: 520))
        window.styleMask = NSWindow.StyleMask([.titled, .closable, .miniaturizable])
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil as AnyObject?)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    func showOnboarding() {
        if let existing = onboardingWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = OnboardingView(onComplete: { [weak self] in
            guard let self else { return }
            self.onboardingWindow?.close()
            if PermissionsManager.hasAccessibilityPermission() {
                self.gestureEngine?.start()
            }
        })
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to TrackpadVolumeKnob"
        window.setContentSize(NSSize(width: 520, height: 440))
        window.styleMask = NSWindow.StyleMask([.titled, .closable])
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil as AnyObject?)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    @objc private func recheckPermissions() {
        if PermissionsManager.hasAccessibilityPermission() {
            gestureEngine?.start()
        } else {
            // Show onboarding with the reset flow — guides user to clear
            // the stale TCC entry and re-enable in System Settings.
            showOnboarding()
        }
    }
}
