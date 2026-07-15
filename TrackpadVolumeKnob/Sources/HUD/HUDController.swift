// HUDController.swift
// Shows and auto-hides the floating volume HUD window.
import AppKit
import SwiftUI

@MainActor
public final class HUDController {

    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?
    private var hudState = HUDState()

    public init() {}

    /// Show (or update) the HUD with the current volume level [0.0, 1.0].
    public func show(volume: Float) {
        hudState.volume = Double(volume)
        hudState.isVisible = true

        if window == nil {
            createWindow()
        }
        window?.orderFrontRegardless()

        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.hudState.isVisible = false
            }
            try? await Task.sleep(for: .seconds(0.3))
            self.window?.orderOut(nil)
        }
    }

    private func createWindow() {
        let hosting = NSHostingView(rootView: HUDView(state: hudState))
        hosting.frame = NSRect(x: 0, y: 0, width: 160, height: 160)

        let win = NSWindow(
            contentRect: hosting.frame,
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        win.contentView = hosting
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.ignoresMouseEvents = true
        win.hasShadow = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        positionNearCursor(window: win)
        self.window = win
    }

    private func positionNearCursor(window: NSWindow) {
        let cursor = NSEvent.mouseLocation
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let size = window.frame.size

        var origin = NSPoint(
            x: cursor.x - size.width / 2,
            y: cursor.y - size.height - 20
        )

        origin.x = max(screenFrame.minX + 8, min(origin.x, screenFrame.maxX - size.width - 8))
        origin.y = max(screenFrame.minY + 8, min(origin.y, screenFrame.maxY - size.height - 8))

        window.setFrameOrigin(origin)
    }
}
