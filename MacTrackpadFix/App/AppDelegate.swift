// AppDelegate.swift
// Root coordinator: owns the menu bar item, gesture pipeline, and window lifecycle.
import AppKit
import SwiftUI
import MacTrackpadFixCore
import Sparkle

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
    private(set) var updaterManager: UpdaterManager!
    private var scrollEventMonitor: Any?
    // MARK: - App lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the Dock icon — pure menu bar app
        NSApp.setActivationPolicy(.accessory)

        // Initialize Sparkle updater (starts scheduled checks automatically)
        updaterManager = UpdaterManager()

        // Build the dependency graph
        let appSettings = AppSettings.shared

        // Sync auto-check setting: Core's AppSettings → Sparkle
        updaterManager.automaticallyChecks = appSettings.autoCheckUpdates
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

        // On first launch after an update, reset stale TCC entry so the user
        // only needs to flip the toggle — no confusing "already checked but broken" state.
        handlePostUpdateTCCReset()

        if !PermissionsManager.hasAccessibilityPermission() {
            showOnboarding()
        } else {
            gestureEngine?.start()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        gestureEngine?.stop()
    }

    public func applicationWillResignActive(_ notification: Notification) {
        // Nothing — we want gestures to work even when not active
    }

    // Stop fling and reset gesture state on sleep/lock to prevent
    // CVDisplayLink running against an invalid display after wake.
    public func applicationWillHide(_ notification: Notification) {
        gestureEngine?.resetGestureState()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "speaker.wave.2.circle",
                accessibilityDescription: "Mac Trackpad Fix"
            )
            button.target = self
        }

        statusItem?.menu = buildMenu()

        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, AppSettings.shared.hoverScrollEnabled else { return event }
            guard let button = self.statusItem?.button, let window = button.window else { return event }
            
            let mouseLoc = NSEvent.mouseLocation
            if window.frame.contains(mouseLoc) {
                self.handleHoverScroll(event)
                return nil
            }
            return event
        }
    }

    private func handleHoverScroll(_ event: NSEvent) {
        let delta = Float(event.scrollingDeltaY) * 0.05
        guard abs(delta) > 0.001 else { return }

        let target = AppSettings.shared.hoverScrollTarget
        switch target {
        case .volume:
            self.volumeController?.adjustVolume(by: delta)
            self.volumeController?.showHUD(increasing: delta > 0)
        case .brightness:
            BrightnessController.shared.adjustBrightness(by: delta)
        default: break
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Mac Trackpad Fix", action: nil, keyEquivalent: "")
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

        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        let permItem = NSMenuItem(
            title: "Re-check Permissions",
            action: #selector(recheckPermissions),
            keyEquivalent: ""
        )
        permItem.target = self
        menu.addItem(permItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Mac Trackpad Fix",
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
        window.title = "Welcome to Mac Trackpad Fix"
        window.setContentSize(NSSize(width: 520, height: 440))
        window.styleMask = NSWindow.StyleMask([.titled, .closable])
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil as AnyObject?)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    @objc private func checkForUpdates() {
        updaterManager.checkForUpdates()
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

    // MARK: - Post-update TCC reset

    /// Detects first launch after a binary change via modification date (not SHA256)
    /// and resets the stale TCC entry so the user only needs to flip the toggle.
    private func handlePostUpdateTCCReset() {
        guard let executableURL = Bundle.main.executableURL else { return }

        // Use file modification date — fast, no binary read, no SHA256
        let mtime = (try? FileManager.default.attributesOfItem(atPath: executableURL.path))?[.modificationDate] as? Date
        let currentKey = mtime.map { String(Int($0.timeIntervalSince1970)) } ?? ""
        let lastKey = UserDefaults.standard.string(forKey: "LastLaunchedBinaryMtime") ?? ""

        if currentKey != lastKey {
            PermissionsManager.resetAccessibilityTrust()
            if !currentKey.isEmpty {
                UserDefaults.standard.set(currentKey, forKey: "LastLaunchedBinaryMtime")
            }
        }
    }
}
