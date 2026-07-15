// GestureEngine.swift
// Observes rotation gesture events system-wide.
//
// KEY INSIGHT: NSEvent.addGlobalMonitorForEvents only fires when ANOTHER app
// is frontmost. For a LSUIElement menu bar app with no window, we are never
// frontmost, so the global monitor alone produces nothing.
//
// SOLUTION: Use a local monitor (fires when WE are the event target) AND
// call NSApp.beginReceivingRemoteControlEvents() + set activation policy so
// the run loop accepts events. But the real fix for a windowless app is to
// use BOTH monitors simultaneously — the global one catches everything when
// other apps are active (which is almost always true for a menu bar app).
//
// In practice: a menu bar app with LSUIElement=true is never "active" in the
// NSApp sense, so we only get global events (other app frontmost). This IS
// the normal case — the user has Finder/Chrome/etc in front, rotates, we get it.
// The only case we miss is when the desktop itself is focused (no app windows).
//
// For complete coverage we also use a CGEventTap as a fallback.

import AppKit
import CoreGraphics

// MARK: - Raw event type

/// A raw rotation sample delivered by the OS.
public struct RotationEvent: Sendable {
    public let degrees: Double
    public let timestamp: TimeInterval
    public let phase: NSEvent.Phase

    public init(degrees: Double, timestamp: TimeInterval, phase: NSEvent.Phase) {
        self.degrees = degrees
        self.timestamp = timestamp
        self.phase = phase
    }
}

// MARK: - Protocol

@MainActor
public protocol GestureEngineDelegate: AnyObject {
    func gestureEngine(_ engine: GestureEngine, didReceive event: RotationEvent)
    func gestureEngineDidBeginGesture(_ engine: GestureEngine)
    func gestureEngineDidEndGesture(_ engine: GestureEngine)
}

// MARK: - GestureEngine

@MainActor
public final class GestureEngine {

    private let settings: AppSettings
    public weak var delegate: GestureEngineDelegate?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false

    public init(settings: AppSettings, interpreter: GestureInterpreter) {
        self.settings = settings
        self.delegate = interpreter
    }

    // MARK: - Lifecycle

    public func start() {
        guard !isRunning else { return }
        guard PermissionsManager.hasAccessibilityPermission() else {
            Logger.warning("GestureEngine: Accessibility permission not granted.")
            return
        }

        let mask: NSEvent.EventTypeMask = [.rotate]

        // Global monitor: fires when OTHER apps are frontmost (the common case).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in self.handle(event) }
        }

        // Local monitor: fires when OUR app is the event target.
        // Needed if the user somehow activates our app window (e.g. settings window).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            Task { @MainActor in self.handle(event) }
            return event
        }

        // CGEventTap fallback: catches gesture events at the session level,
        // independent of which app is frontmost. This covers the desktop/Finder case.
        installCGEventTap()

        isRunning = true
        Logger.info("GestureEngine: started (global + local monitors + CGEventTap).")
    }

    public func stop() {
        guard isRunning else { return }

        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor = nil }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = nil
        }

        isRunning = false
        Logger.info("GestureEngine: stopped.")
    }

    // MARK: - CGEventTap

    private func installCGEventTap() {
        // Gesture events sit at CGEventType rawValue 29.
        let gestureType = CGEventType(rawValue: 29)!
        let eventMask = CGEventMask(1 << gestureType.rawValue)

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, _, cgEvent, userInfo in
                guard let userInfo else {
                    return Unmanaged.passRetained(cgEvent)
                }
                let engine = Unmanaged<GestureEngine>.fromOpaque(userInfo).takeUnretainedValue()
                // Wrap in NSEvent to read .rotation
                if let nsEvent = NSEvent(cgEvent: cgEvent),
                   nsEvent.type == .rotate {
                    Task { @MainActor in engine.handle(nsEvent) }
                }
                return Unmanaged.passRetained(cgEvent)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else {
            Logger.warning("GestureEngine: CGEventTap creation failed.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        Logger.info("GestureEngine: CGEventTap installed.")
    }

    // MARK: - Event handling

    private func handle(_ event: NSEvent) {
        // Fallback mode: only act while modifier is held
        if settings.fallbackMode {
            guard isFallbackModifierDown() else { return }
        }

        let degrees = Double(event.rotation)

        switch event.phase {
        case .began:   delegate?.gestureEngineDidBeginGesture(self)
        case .ended, .cancelled: delegate?.gestureEngineDidEndGesture(self)
        default: break
        }

        guard degrees != 0 else { return }

        if settings.debugLogging {
            Logger.debug("GestureEngine: rotation \(String(format: "%.3f", degrees))° phase=\(event.phase.rawValue)")
        }

        delegate?.gestureEngine(self, didReceive: RotationEvent(
            degrees: degrees,
            timestamp: event.timestamp,
            phase: event.phase
        ))
    }

    private func isFallbackModifierDown() -> Bool {
        let flags = NSEvent.modifierFlags
        switch settings.fallbackModifier {
        case .fn:      return flags.contains(.function)
        case .control: return flags.contains(.control)
        case .option:  return flags.contains(.option)
        case .command: return flags.contains(.command)
        }
    }
}
