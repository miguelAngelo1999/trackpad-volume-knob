// GestureInterpreter.swift
// Converts raw RotationEvents into continuous volume/brightness deltas.
//
// Key design decisions matching mac-mouse-fix feel:
//   • Direct degrees→scalar mapping — no "steps" quantisation. Every
//     fraction of a degree produces a proportional volume change.
//   • degreesForFullRange: rotating this many degrees sweeps 0→100%.
//     Default 180° — half a full rotation = full volume sweep.
//   • postMediaKey fires ONCE at gesture end (and once when fling ends),
//     not on every event. This prevents the OS from snapping volume to
//     discrete 6.25% increments mid-gesture.
//   • Acceleration: optional power curve blended in at high speed so a
//     fast flick covers more range, a slow deliberate turn is precise.

import Foundation
import AppKit

// MARK: - GestureInterpreter

@MainActor
public final class GestureInterpreter: GestureEngineDelegate {

    // MARK: Dependencies
    private let settings: AppSettings
    private let volumeController: VolumeController
    private let brightnessController: BrightnessController
    private let hudController: HUDController

    // MARK: Fling (post-lift coast only)
    private let flingEngine = FlingEngine()

    // MARK: Haptic feedback
    private let hapticEngine = HapticEngine()

    // MARK: Accumulator + tracking state
    private var accumulatedDegrees: Double = 0
    private var lastEventTimestamp: TimeInterval = 0
    private var gestureNetDegrees: Double = 0
    private var lockedTarget: GestureTarget = .volume   // resolved once at gesture begin

    // MARK: Gesture type lock — prevents rotate/pinch cross-contamination
    private enum ActiveGesture { case none, rotate, pinch }
    private var activeGesture: ActiveGesture = .none
    private var rotateEventCount: Int = 0
    private var pinchEventCount: Int = 0

    // MARK: Gesture classifier — ratio-based disambiguation
    // Accumulate magnitude of both types during the classification window,
    // then lock to whichever is dominant. Prevents stray leaks from firing.
    private var classifyWindowRotateMag: Double = 0  // sum of |degrees| so far
    private var classifyWindowPinchMag: Double = 0   // sum of |magnification| so far
    private var classifyWindowEvents: Int = 0
    private let classifyWindowSize: Int = 4           // events before committing
    // Pinch magnification is ~0.05 per event; rotation is ~3° per event.
    // Normalize pinch by this factor so they're on comparable scales.
    private let pinchNormFactor: Double = 60.0        // 1 unit pinch ≈ 60° rotation

    // MARK: Init

    public init(
        settings: AppSettings,
        volumeController: VolumeController,
        brightnessController: BrightnessController,
        hudController: HUDController
    ) {
        self.settings = settings
        self.volumeController = volumeController
        self.brightnessController = brightnessController
        self.hudController = hudController
    }

    // MARK: - GestureEngineDelegate

    public func gestureEngineDidBeginGesture(_ engine: GestureEngine) {
        accumulatedDegrees = 0
        lastEventTimestamp = 0
        gestureNetDegrees = 0
        lockedTarget = resolvedTarget()
        flingEngine.reset()
        hapticEngine.reset()
        rotateEventCount = 0
        classifyWindowRotateMag = 0
        classifyWindowPinchMag = 0
        classifyWindowEvents = 0
        if activeGesture == .none { activeGesture = .rotate }
    }

    public func gestureEngineDidEndGesture(_ engine: GestureEngine) {
        accumulatedDegrees = 0
        if activeGesture == .rotate { activeGesture = .none }
        rotateEventCount = 0
        classifyWindowRotateMag = 0
        classifyWindowPinchMag = 0
        classifyWindowEvents = 0

        switch lockedTarget {
        case .volume:
            let increasing = gestureNetDegrees >= 0
            volumeController.showHUD(increasing: increasing)
        case .brightness:
            break
        }

        let target = lockedTarget
        flingEngine.startFling { [weak self] delta in
            self?.applyDelta(delta, target: target, showHUD: false)
        }
    }

    // MARK: - Pinch delegate methods

    public func gestureEngineDidBeginPinch(_ engine: GestureEngine) {
        hapticEngine.reset()
        pinchEventCount = 0
        classifyWindowRotateMag = 0
        classifyWindowPinchMag = 0
        classifyWindowEvents = 0
        if activeGesture == .none { activeGesture = .pinch }
    }

    public func gestureEngineDidEndPinch(_ engine: GestureEngine) {
        if activeGesture == .pinch { activeGesture = .none }
        pinchEventCount = 0
        classifyWindowRotateMag = 0
        classifyWindowPinchMag = 0
        classifyWindowEvents = 0
    }

    public func gestureEngine(_ engine: GestureEngine, didReceivePinch event: PinchEvent) {
        guard settings.pinchEnabled else { return }

        // If rotation is active, ignore pinch entirely — rotation takes priority.
        // macOS leaks small magnify events during rotation; the magnitude ratio
        // test catches any ambiguous cases at gesture start.
        guard activeGesture != .rotate else { return }

        let mag = abs(event.magnification)

        // If no gesture is committed yet, use ratio to decide.
        // A real pinch has much larger magnification relative to any rotation leak.
        if activeGesture == .none {
            classifyWindowPinchMag += mag * pinchNormFactor
            classifyWindowEvents += 1
            if classifyWindowEvents < classifyWindowSize { return }
            // Commit based on ratio
            if classifyWindowRotateMag > classifyWindowPinchMag {
                activeGesture = .rotate
            } else {
                activeGesture = .pinch
            }
            if settings.debugLogging {
                Logger.debug("Classifier: committed to \(activeGesture) (rot=\(String(format:"%.1f",classifyWindowRotateMag)) pinch=\(String(format:"%.1f",classifyWindowPinchMag))")
            }
            if activeGesture == .rotate { return }
        }

        pinchEventCount += 1

        let scalar = event.magnification * settings.sensitivity * 20.0
        let finalDelta = Float(scalar)
        guard abs(finalDelta) > 0.0001 else { return }

        let target: GestureTarget = settings.pinchTarget == .brightness ? .brightness : .volume

        if settings.debugLogging {
            Logger.debug("Interpreter: pinch target=\(target) Δ=\(String(format:"%.5f", finalDelta))")
        }

        switch target {
        case .volume:
            volumeController.adjustVolume(by: finalDelta)
            hapticEngine.feedback(value: volumeController.currentVolume,
                                  delta: finalDelta, target: .volume,
                                  level: settings.hapticLevel)
        case .brightness:
            brightnessController.adjustBrightness(by: finalDelta)
            hapticEngine.feedback(value: brightnessController.currentBrightness(),
                                  delta: finalDelta, target: .brightness,
                                  level: settings.hapticLevel)
        }
    }

    public func gestureEngine(_ engine: GestureEngine, didReceive event: RotationEvent) {
        // Track rotation magnitude for classifier (in case pinch fires first)
        classifyWindowRotateMag += abs(event.degrees)

        // If pinch is committed, ignore rotation
        guard activeGesture != .pinch else { return }

        // Rotation always acts immediately — no classification window needed.
        // The activeGesture = .rotate set in gestureEngineDidBeginGesture handles
        // blocking stray pinch events during rotation.
        rotateEventCount += 1
        var delta = event.degrees

        // 1. Sign: NSEvent.rotation positive = CCW. Negate so CW = positive = "increase".
        delta = -delta
        if settings.invertDirection { delta = -delta }

        // 2. Dead zone accumulator — absorbs jitter without quantising output.
        accumulatedDegrees += delta
        guard abs(accumulatedDegrees) >= settings.deadZoneDegrees else { return }

        // 3. dt for FlingEngine EMA velocity tracking.
        let now = event.timestamp
        let dt = lastEventTimestamp > 0 ? (now - lastEventTimestamp) : 0.016
        lastEventTimestamp = now

        let deg = accumulatedDegrees
        accumulatedDegrees = 0
        gestureNetDegrees += deg

        // 4. Track for fling exit-velocity.
        flingEngine.track(degrees: deg, dt: dt)

        // 5. Apply using locked target — don't re-evaluate modifier mid-gesture.
        applyDelta(deg, target: lockedTarget, showHUD: false)
    }

    // MARK: - Delta application

    /// degrees: signed rotation delta this tick.
    /// showHUD: post a media key to surface the native HUD (use only at gesture/fling end).
    private func applyDelta(_ degrees: Double, target: GestureTarget, showHUD: Bool) {
        // Direct mapping: degreesForFullRange degrees = 1.0 (full scalar range).
        // sensitivity scales that — default 1.0 means 180° sweeps full range.
        let degreesForFullRange = max(10.0, settings.degreesPerStep * 36.0)
        // ↑ degreesPerStep is repurposed as a sensitivity multiplier in the UI:
        //   degreesPerStep=5 → degreesForFullRange=180°  (good default)
        //   degreesPerStep=2 → degreesForFullRange=72°   (more sensitive)
        //   degreesPerStep=10 → degreesForFullRange=360° (less sensitive)

        var scalar = degrees / degreesForFullRange

        // Acceleration: blend in a power curve at high speed.
        scalar = applyAcceleration(scalar: scalar, degrees: abs(degrees))

        // Final sensitivity multiplier.
        let finalDelta = Float(scalar * settings.sensitivity * 20.0)
        // × 20 because sensitivity default 0.05 × 20 = 1.0 → full mapping

        guard abs(finalDelta) > 0.0001 else { return }

        if settings.debugLogging {
            Logger.debug("Interpreter: target=\(target) Δ°=\(String(format:"%.3f",degrees)) Δ=\(String(format:"%.5f",finalDelta))")
        }

        switch target {
        case .volume:
            volumeController.adjustVolume(by: finalDelta)
            if showHUD { volumeController.showHUD(increasing: finalDelta > 0) }
            hapticEngine.feedback(
                value: volumeController.currentVolume,
                delta: finalDelta,
                target: .volume,
                level: settings.hapticLevel
            )
        case .brightness:
            brightnessController.adjustBrightness(by: finalDelta)
            hapticEngine.feedback(
                value: brightnessController.currentBrightness(),
                delta: finalDelta,
                target: .brightness,
                level: settings.hapticLevel
            )
        }
    }

    // MARK: - Target resolution

    private func resolvedTarget() -> GestureTarget {
        let base = settings.gestureTarget
        if settings.brightnessModifier != .none && isBrightnessModifierDown() {
            return base == .volume ? .brightness : .volume
        }
        return base
    }

    private func isBrightnessModifierDown() -> Bool {
        let flags = NSEvent.modifierFlags
        switch settings.brightnessModifier {
        case .none:    return false
        case .fn:      return flags.contains(.function)
        case .control: return flags.contains(.control)
        case .option:  return flags.contains(.option)
        case .command: return flags.contains(.command)
        }
    }

    // MARK: - Acceleration

    /// Blends in a power curve at high rotational speed so fast flings
    /// cover more range while slow deliberate turns stay precise.
    private func applyAcceleration(scalar: Double, degrees: Double) -> Double {
        let accel = max(1.0, settings.acceleration)
        guard accel > 1.0 else { return scalar }

        // velocityFactor: 0 at slow (< 2°/event), 1 at fast (> 30°/event)
        let velocityFactor = min(1.0, max(0.0, (degrees - 2.0) / 28.0))
        let sign: Double = scalar >= 0 ? 1 : -1
        let mag = abs(scalar)
        let powered = pow(mag, 1.0 / accel) // accel > 1 → gentler curve for fine control
        let blended = mag + (powered - mag) * velocityFactor
        return sign * blended
    }
}
