// GestureInterpreter.swift
// Converts raw RotationEvents into volume or brightness deltas,
// with flywheel momentum via FlingEngine for smooth fling/coast behaviour.
//
// Routing logic:
//   • settings.gestureTarget == .volume     → VolumeController (default)
//   • settings.gestureTarget == .brightness → BrightnessController
//   • settings.brightnessModifier != .none  → hold that key to switch to brightness
//     while base target remains volume (and vice-versa)
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

    // MARK: Flywheel / fling
    private let flingEngine = FlingEngine()

    // MARK: Accumulator state (used during active gesture only)
    private var accumulatedDegrees: Double = 0
    private var lastEventTimestamp: TimeInterval = 0

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

        // Spin up the flywheel; its callback applies deltas in real-time
        // while fingers are still on the trackpad.
        // Callback arrives on main queue (DispatchQueue.main.async in FlingEngine).
        let target = resolvedTarget()
        flingEngine.beginGesture { [weak self] degrees in
            self?.applyDelta(degrees, target: target)
        }
    }

    public func gestureEngineDidEndGesture(_ engine: GestureEngine) {
        accumulatedDegrees = 0

        // Hand off to DragCurve fling so momentum coasts after lift-off.
        // Callback arrives on main queue (DispatchQueue.main.async in FlingEngine).
        let target = resolvedTarget()
        flingEngine.endGesture { [weak self] degrees in
            self?.applyDelta(degrees, target: target)
        }
    }

    public func gestureEngine(_ engine: GestureEngine, didReceive event: RotationEvent) {
        var delta = event.degrees

        // 1. Invert: NSEvent.rotation positive = CCW on macOS.
        //    We negate so CW = positive = "increase" by default.
        delta = -delta
        if settings.invertDirection { delta = -delta }

        // 2. Dead zone — ignore tiny noise
        accumulatedDegrees += delta
        guard abs(accumulatedDegrees) >= settings.deadZoneDegrees else { return }

        // 3. dt for EMA velocity in FlingEngine
        let now = event.timestamp
        let dt = lastEventTimestamp > 0 ? (now - lastEventTimestamp) : 0.016
        lastEventTimestamp = now

        // 4. Feed into flywheel — this both displays the change immediately
        //    and builds up exit velocity for the post-lift fling.
        flingEngine.pedal(degrees: accumulatedDegrees, dt: dt)

        // 5. Reset accumulator once consumed
        accumulatedDegrees = 0
    }

    // MARK: - Delta application

    /// Converts a raw degree delta → controller call, applying sensitivity + acceleration.
    private func applyDelta(_ degrees: Double, target: GestureTarget) {
        let degreesPerStep = max(0.5, settings.degreesPerStep)
        let rawSteps = degrees / degreesPerStep
        guard abs(rawSteps) >= 0.05 else { return }  // sub-threshold ticks during coasting

        let accelerated = applyAcceleration(steps: rawSteps, speed: abs(degrees))
        let scalarDelta = Float(accelerated * settings.sensitivity)

        if settings.debugLogging {
            Logger.debug("Interpreter: target=\(target) Δ°=\(String(format: "%.3f", degrees)) steps=\(String(format: "%.3f", rawSteps)) Δ=\(String(format: "%.4f", scalarDelta))")
        }

        switch target {
        case .volume:
            volumeController.adjustVolume(by: scalarDelta)
        case .brightness:
            brightnessController.adjustBrightness(by: scalarDelta)
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

    // MARK: - Acceleration curve

    private func applyAcceleration(steps: Double, speed: Double) -> Double {
        let accel = max(1.0, settings.acceleration)
        let sign: Double = steps >= 0 ? 1 : -1
        let magnitude = abs(steps)
        let velocityFactor = min(1.0, speed / 60.0)
        let powered = pow(magnitude, accel)
        let blended = magnitude + (powered - magnitude) * velocityFactor
        return sign * blended
    }
}
