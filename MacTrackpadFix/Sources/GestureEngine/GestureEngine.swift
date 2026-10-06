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

/// A raw pinch/magnify sample delivered by the OS.
public struct PinchEvent: Sendable {
    public let magnification: Double   // positive = spread, negative = pinch
    public let timestamp: TimeInterval
    public let phase: NSEvent.Phase

    public init(magnification: Double, timestamp: TimeInterval, phase: NSEvent.Phase) {
        self.magnification = magnification
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

    func gestureEngine(_ engine: GestureEngine, didReceivePinch event: PinchEvent)
    func gestureEngineDidBeginPinch(_ engine: GestureEngine)
    func gestureEngineDidEndPinch(_ engine: GestureEngine)
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
    private var tapWatchdog: DispatchSourceTimer?

    // MARK: - Gesture type disambiguation
    // Rotation and pinch events fire simultaneously at gesture start.
    // We use a 3-stage heuristic to decide which to honour:
    //   1. Mutex: once one type is committed, the other is blocked until it ends.
    //   2. Decision window: first 80ms, accumulate both; commit to the dominant one.
    //   3. Minimum threshold: pinch needs ≥ 0.015 total magnitude before it fires.

    private enum GestureLock { case none, rotation, pinch }
    private var gestureLock: GestureLock = .none

    // Decision window state
    private var decidingStart: CFTimeInterval = 0
    private var pendingRotationDeg: Double = 0    // accumulated |°| during window
    private var pendingMagAbs: Double = 0          // accumulated |mag| during window
    private let decisionWindowSecs: Double = 0.08  // 80 ms
    // Normalisation factors: what magnitude constitutes a "full" gesture per type
    private let rotNorm: Double  = 8.0    // 8° = strong rotation signal
    private let magNorm: Double  = 0.06   // 0.06 mag = strong pinch signal
    private let pinchMinThreshold: Double = 0.015  // must accumulate this much before acting

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

        let mask: NSEvent.EventTypeMask = [.rotate, .magnify]

        // Global monitor: fires when OTHER apps are frontmost (the common case).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return }
            DispatchQueue.main.async { self.handle(event) }
        }

        // Local monitor: fires when OUR app is the event target.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            DispatchQueue.main.async { self.handle(event) }
            return event
        }

        // CGEventTap fallback: catches gesture events at the session level,
        // independent of which app is frontmost. This covers the desktop/Finder case.
        installCGEventTap()

        isRunning = true
        Logger.info("GestureEngine: started (global + local monitors + CGEventTap).")
        startTapWatchdog()

        // Stop any running fling when display sleeps — CVDisplayLink
        // can crash if it fires after display invalidation.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleDisplaySleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
    }

    @objc private func handleDisplaySleep() {
        resetGestureState()
        Logger.info("GestureEngine: display slept — fling + gesture state reset.")
    }

    /// Resets in-flight gesture state and stops any running fling.
    /// Safe to call from any context (sleep, screen lock, app switching).
    public func resetGestureState() {
        gestureLock = .none
        pendingRotationDeg = 0
        pendingMagAbs = 0
        cachedFrontmostID = nil
        cachedFrontmostTime = 0
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
        stopTapWatchdog()
        gestureLock = .none
        pendingRotationDeg = 0
        pendingMagAbs = 0
        Logger.info("GestureEngine: stopped.")
    }

    // MARK: - Tap Watchdog
    // macOS can silently disable CGEventTaps. Check every 5s and re-enable if needed.

    private func startTapWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                Logger.warning("GestureEngine: CGEventTap was disabled — re-enabling.")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        timer.resume()
        tapWatchdog = timer
    }

    private func stopTapWatchdog() {
        tapWatchdog?.cancel()
        tapWatchdog = nil
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
                // Wrap in NSEvent to read .rotation / .magnification
                // Use DispatchQueue.main.async (not Task) to avoid Swift concurrency
                // task pile-up that can cause macOS to silently disable the tap.
                if let nsEvent = NSEvent(cgEvent: cgEvent) {
                    if nsEvent.type == .rotate {
                        DispatchQueue.main.async { engine.handle(nsEvent) }
                    } else if nsEvent.type == .magnify {
                        DispatchQueue.main.async { engine.handlePinch(nsEvent) }
                    }
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
        // Exclusion list: pass through to apps that use rotation natively.
        if let bid = frontmostBundleID(), settings.isExcluded(bid) {
            if settings.debugLogging {
                Logger.debug("GestureEngine: skipping — \(bid) is excluded")
            }
            return
        }

        // Fallback mode: only act while modifier is held
        if settings.fallbackMode {
            guard isFallbackModifierDown() else { return }
        }

        // Route by event type
        if event.type == .magnify {
            handlePinch(event)
            return
        }

        let degrees = Double(event.rotation)

        // --- Gesture mutex + decision window ---
        switch event.phase {
        case .began:
            if gestureLock == .none {
                // Start decision window — don't commit yet
                decidingStart  = event.timestamp
                pendingRotationDeg = abs(degrees)
                pendingMagAbs  = 0
            }
            if gestureLock == .pinch { return }   // pinch won the window — ignore rotation
            if gestureLock == .none  { /* deciding — fall through to send .began */ }
            gestureLock = .rotation
            delegate?.gestureEngineDidBeginGesture(self)

        case .ended, .cancelled:
            if gestureLock == .rotation { gestureLock = .none }
            delegate?.gestureEngineDidEndGesture(self)

        default:
            // In-flight rotation event — check if pinch already won
            if gestureLock == .pinch { return }
            // Still deciding? accumulate rotation signal
            if event.timestamp - decidingStart < decisionWindowSecs {
                pendingRotationDeg += abs(degrees)
                // Check dominance: if rotation already dominates, commit early
                if pendingRotationDeg / rotNorm > pendingMagAbs / magNorm + 0.3 {
                    gestureLock = .rotation
                }
            }
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

    private func handlePinch(_ event: NSEvent) {
        guard settings.pinchEnabled else { return }

        // Exclusion list
        if let bid = frontmostBundleID(), settings.isExcluded(bid) { return }

        let mag = Double(event.magnification)

        // --- Gesture mutex + decision window ---
        switch event.phase {
        case .began:
            if gestureLock == .rotation { return }  // rotation already won — ignore pinch
            if gestureLock == .none {
                decidingStart  = event.timestamp
                pendingMagAbs  = abs(mag)
                pendingRotationDeg = 0
            }
            // Don't commit the lock yet — wait for dominance or window expiry
            delegate?.gestureEngineDidBeginPinch(self)

        case .ended, .cancelled:
            if gestureLock == .pinch { gestureLock = .none }
            delegate?.gestureEngineDidEndPinch(self)
            return

        default:
            if gestureLock == .rotation { return }  // rotation won — suppress pinch
            pendingMagAbs += abs(mag)

            // Decision window: choose dominant gesture
            if gestureLock == .none {
                let elapsed = event.timestamp - decidingStart
                let rotScore = pendingRotationDeg / rotNorm
                let magScore = pendingMagAbs      / magNorm

                if elapsed >= decisionWindowSecs || abs(rotScore - magScore) > 0.3 {
                    // Window expired or one clearly dominates
                    if rotScore > magScore {
                        gestureLock = .rotation
                        return  // rotation won — suppress this pinch event
                    } else {
                        gestureLock = .pinch
                    }
                } else {
                    // Still deciding — suppress pinch for now (conservatively)
                    return
                }
            }

            // Minimum threshold: don't act until enough magnification accumulated
            guard pendingMagAbs >= pinchMinThreshold else { return }
        }

        guard mag != 0 else { return }

        if settings.debugLogging {
            Logger.debug("GestureEngine: pinch \(String(format: "%.4f", mag)) phase=\(event.phase.rawValue) lock=\(gestureLock)")
        }

        delegate?.gestureEngine(self, didReceivePinch: PinchEvent(
            magnification: mag,
            timestamp: event.timestamp,
            phase: event.phase
        ))
    }

    // Frontmost app cache — NSWorkspace.frontmostApplication is an XPC call.
    // Calling it 50+ times/sec during rotation creates a backlog of objects.
    // Cache with a 150ms TTL so we check at most ~7 times/sec.
    private var cachedFrontmostID: String? = nil
    private var cachedFrontmostTime: CFTimeInterval = 0
    private let frontmostCacheTTL: CFTimeInterval = 0.15

    private func frontmostBundleID() -> String? {
        let now = CACurrentMediaTime()
        if now - cachedFrontmostTime < frontmostCacheTTL {
            return cachedFrontmostID
        }
        cachedFrontmostID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        cachedFrontmostTime = now
        return cachedFrontmostID
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
