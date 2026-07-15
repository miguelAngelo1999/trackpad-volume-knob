// BrightnessController.swift
// Adjusts display brightness and shows the native macOS OSD HUD.
//
// Built-in display: DisplayServices.framework (private) + OSD.framework (private) HUD.
// External displays: same DisplayServices call first; fall back to DDC via BrightnessControllerDDC.
//                    Below hardware zero: software gamma via CGSetDisplayTransferByTable.
//                    HUD: custom overlay (native OSD broken on Tahoe+ for externals).
//
// All private symbols loaded at runtime via dlopen/dlsym.

import AppKit
import CoreGraphics
import Foundation

// MARK: - DisplayServices function pointer types

private typealias DSGetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
private typealias DSSetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

// MARK: - OSD image IDs (OSD.framework private header)

private enum OSDImage: Int64 {
    case brightness = 1
    case volume     = 3
    case muted      = 4
}

// MARK: - BrightnessController

@MainActor
public final class BrightnessController {

    public static let shared = BrightnessController()

    private var ddc: BrightnessControllerDDC?

    // Logical brightness per display: 0.0–1.0 = software gamma, 1.0–2.0 = hardware.
    private var logicalBrightness: [CGDirectDisplayID: Float] = [:]

    private init() {
        loadDisplayServices()
        loadOSDFramework()
        ddc = BrightnessControllerDDC()

        CGDisplayRegisterReconfigurationCallback({ _, _, _ in
            Task { @MainActor in
                BrightnessController.shared.logicalBrightness.removeAll()
                BrightnessController.shared.ddc?.invalidateCaches()
            }
        }, nil)
    }

    // MARK: - Public API

    public func adjustBrightness(by delta: Float) {
        adjustBrightness(by: delta, on: displayUnderCursor())
    }

    public func adjustBrightness(by delta: Float, on displayID: CGDirectDisplayID) {
        let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
        if isBuiltIn {
            adjustBuiltIn(delta: delta, displayID: displayID)
        } else {
            adjustExternal(delta: delta, displayID: displayID)
        }
    }

    // MARK: - Built-in display

    private func adjustBuiltIn(delta: Float, displayID: CGDirectDisplayID) {
        guard let getFn = dsGetBrightness, let setFn = dsSetBrightness else { return }
        var current: Float = 0.5
        guard getFn(displayID, &current) == 0 else { return }
        let newVal = clampF(current + delta * 4.0, 0, 1)
        _ = setFn(displayID, newVal)
        showOSD(displayID: displayID, image: .brightness, value: newVal)
        Logger.debug("BrightnessController: built-in → \(String(format: "%.3f", newVal))")
    }

    // MARK: - External display

    private func adjustExternal(delta: Float, displayID: CGDirectDisplayID) {
        if logicalBrightness[displayID] == nil {
            let hw = readHardwareBrightness(displayID: displayID)
            logicalBrightness[displayID] = 1.0 + hw
        }

        let current = logicalBrightness[displayID]!
        let newLogical = clampF(current + delta * 4.0, 0, 2)
        logicalBrightness[displayID] = newLogical

        let hwValue: Float
        let gammaMultiplier: Float

        if newLogical >= 1.0 {
            hwValue = newLogical - 1.0
            gammaMultiplier = 1.0
        } else {
            hwValue = 0.0
            gammaMultiplier = max(0, newLogical)
        }

        setHardwareBrightness(hwValue, displayID: displayID)
        setGammaMultiplier(gammaMultiplier, displayID: displayID)
        showOSD(displayID: displayID, image: .brightness, value: newLogical / 2.0)

        Logger.debug("BrightnessController: external \(displayID) logical=\(String(format:"%.3f",newLogical)) hw=\(String(format:"%.3f",hwValue)) gamma=\(String(format:"%.3f",gammaMultiplier))")
    }

    // MARK: - Hardware brightness helpers

    private func readHardwareBrightness(displayID: CGDirectDisplayID) -> Float {
        if let getFn = dsGetBrightness {
            var val: Float = 0.5
            if getFn(displayID, &val) == 0 { return val }
        }
        return Float(ddc?.readBrightness(displayID: displayID) ?? 50) / 100.0
    }

    private func setHardwareBrightness(_ value: Float, displayID: CGDirectDisplayID) {
        if let setFn = dsSetBrightness {
            if setFn(displayID, value) == 0 { return }
        }
        ddc?.writeBrightness(Int(value * 100), displayID: displayID)
    }

    // MARK: - Software gamma

    private func setGammaMultiplier(_ multiplier: Float, displayID: CGDirectDisplayID) {
        guard multiplier < 0.999 else {
            CGDisplayRestoreColorSyncSettings()
            return
        }
        let n: UInt32 = 256
        var r = [CGGammaValue](repeating: 0, count: Int(n))
        var g = [CGGammaValue](repeating: 0, count: Int(n))
        var b = [CGGammaValue](repeating: 0, count: Int(n))
        for i in 0..<Int(n) {
            let v = CGGammaValue(Float(i) / 255.0 * multiplier)
            r[i] = v; g[i] = v; b[i] = v
        }
        CGSetDisplayTransferByTable(displayID, n, &r, &g, &b)
    }

    // MARK: - Native OSD HUD

    private func showOSD(displayID: CGDirectDisplayID, image: OSDImage, value: Float) {
        // External displays on Tahoe+ use custom overlay (native OSD is broken there)
        if CGDisplayIsBuiltin(displayID) == 0 && image == .brightness {
            showCustomOverlay(displayID: displayID, value: value)
            return
        }

        guard let cls = NSClassFromString("OSDManager") as? NSObjectProtocol.Type else { return }
        guard let mgr = (cls as AnyObject).perform(Selector(("sharedManager")))?.takeUnretainedValue() else { return }

        // OSDManager.showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:
        // NSInvocation is unavailable in Swift — use objc_msgSend via a C function pointer instead.
        typealias ShowImageFn = @convention(c) (
            AnyObject, Selector,
            Int64,      // imageID
            UInt32,     // displayID
            UInt32,     // priority
            UInt32,     // msecUntilFade
            UInt32,     // filledChiclets
            UInt32,     // totalChiclets
            ObjCBool    // locked
        ) -> Void

        let sel = NSSelectorFromString("showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:")
        guard (mgr as AnyObject).responds(to: sel) else { return }

        let imp = (mgr as AnyObject).method(for: sel)
        let fn = unsafeBitCast(imp, to: ShowImageFn.self)

        let filled = UInt32(clampI(Int(value * 16), 0, 16))
        fn(mgr as AnyObject, sel,
           image.rawValue,
           displayID,
           0x1F4,   // priority
           1000,    // ms until fade
           filled,
           16,
           false)
    }

    // MARK: - Custom overlay (external displays / Tahoe)

    private var overlayWindow: NSWindow?
    private var overlayBarFill: NSView?
    private var overlayIcon: NSImageView?
    private var overlayLabel: NSTextField?
    private var overlayFadeTask: Task<Void, Never>?

    private func ensureOverlayWindow() {
        guard overlayWindow == nil else { return }
        let w: CGFloat = 220, h: CGFloat = 44
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [], backing: .buffered, defer: false
        )
        win.level = .floating
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let content = win.contentView!
        content.wantsLayer = true
        content.layer?.cornerRadius = 12
        content.layer?.masksToBounds = true
        content.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.85).cgColor

        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 10, y: 24, width: w - 20, height: 16)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = NSColor(white: 0.7, alpha: 1)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        content.addSubview(label)

        let icon = NSImageView(frame: NSRect(x: 10, y: 5, width: 16, height: 16))
        icon.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(icon)

        let barBg = NSView(frame: NSRect(x: 32, y: 9, width: w - 44, height: 7))
        barBg.wantsLayer = true
        barBg.layer?.cornerRadius = 3.5
        barBg.layer?.backgroundColor = NSColor(white: 0.3, alpha: 1).cgColor
        content.addSubview(barBg)

        let fill = NSView(frame: NSRect(x: 32, y: 9, width: 0, height: 7))
        fill.wantsLayer = true
        fill.layer?.cornerRadius = 3.5
        fill.layer?.backgroundColor = NSColor.white.cgColor
        content.addSubview(fill)

        overlayWindow = win; overlayBarFill = fill
        overlayIcon = icon; overlayLabel = label
    }

    private func showCustomOverlay(displayID: CGDirectDisplayID, value: Float) {
        ensureOverlayWindow()
        guard let win = overlayWindow, let fill = overlayBarFill,
              let label = overlayLabel, let icon = overlayIcon else { return }

        let screenFrame = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        })?.frame ?? NSScreen.main?.frame ?? .zero

        win.setFrameOrigin(NSPoint(
            x: screenFrame.midX - win.frame.width / 2,
            y: screenFrame.minY + 80
        ))

        label.stringValue = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        })?.localizedName ?? "External Display"

        if let img = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil) {
            icon.image = img.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            )
            icon.contentTintColor = .white
        }

        var fillFrame = fill.frame
        fillFrame.size.width = CGFloat(clampF(value, 0, 1)) * (win.frame.width - 44)
        fill.frame = fillFrame

        win.alphaValue = 1
        win.orderFrontRegardless()

        overlayFadeTask?.cancel()
        overlayFadeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.3
                    win.animator().alphaValue = 0
                }
            }
        }
    }

    // MARK: - Display under cursor

    public func displayUnderCursor() -> CGDirectDisplayID {
        let pt = NSEvent.mouseLocation
        var displayID = CGMainDisplayID()
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(CGPoint(x: pt.x, y: pt.y), 1, &displayID, &count)
        return count > 0 ? displayID : CGMainDisplayID()
    }

    // MARK: - Private framework loading

    private var dsGetBrightness: DSGetBrightnessFn?
    private var dsSetBrightness: DSSetBrightnessFn?

    private func loadDisplayServices() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY
        ) else { return }
        dsGetBrightness = unsafeBitCast(dlsym(handle, "DisplayServicesGetBrightness"), to: DSGetBrightnessFn?.self)
        dsSetBrightness = unsafeBitCast(dlsym(handle, "DisplayServicesSetBrightness"), to: DSSetBrightnessFn?.self)
    }

    private func loadOSDFramework() {
        dlopen("/System/Library/PrivateFrameworks/OSD.framework/OSD", RTLD_LAZY)
    }
}

// MARK: - Internal clamp helpers

@inline(__always) private func clampF(_ v: Float, _ lo: Float, _ hi: Float) -> Float { Swift.min(Swift.max(v, lo), hi) }
@inline(__always) private func clampI(_ v: Int,   _ lo: Int,   _ hi: Int)   -> Int   { Swift.min(Swift.max(v, lo), hi) }
