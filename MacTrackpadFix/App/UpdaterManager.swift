// UpdaterManager.swift
// Wraps Sparkle's SPUStandardUpdaterController for use from AppDelegate and SwiftUI.
//
// Sparkle lives in the App target (not Core) because it needs to be linked against the
// executable — the framework embeds XPC services that must live beside the binary.

import Foundation
import Sparkle

/// Thin wrapper around Sparkle's updater. Created once in AppDelegate, shared with Settings.
@MainActor
public final class UpdaterManager: ObservableObject {

    let updaterController: SPUStandardUpdaterController

    /// Whether automatic update checks are enabled (mirrors Sparkle's automaticallyChecksForUpdates).
    @Published public var automaticallyChecks: Bool {
        didSet { updaterController.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    public init() {
        // startingUpdater: true → Sparkle starts its scheduled update checks immediately.
        // updaterDelegate / userDriverDelegate: nil → use Sparkle defaults.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        automaticallyChecks = updaterController.updater.automaticallyChecksForUpdates
    }

    /// Trigger a manual "Check for Updates…" from the menu bar.
    public func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Whether the updater can currently check (not already checking).
    public var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }
}
