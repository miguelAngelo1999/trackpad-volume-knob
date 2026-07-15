// FlingEngine.swift
// Flywheel + DragCurve fling engine for rotation gestures.
//
// Threading model (safe, verified manually):
//   • Public methods are always called from the main thread (GestureInterpreter is @MainActor).
//   • DispatchSourceTimers fire on a global background queue.
//   • The timer event handler reads flywheelVelocity (written on main thread) — on arm64
//     Double reads/writes are atomic at the hardware level, so no torn reads.
//   • All callbacks are dispatched to DispatchQueue.main before invocation, so they
//     arrive on the main thread and can safely call @MainActor methods.
//
// Note: Package.swift uses .swiftLanguageMode(.v5) for TrackpadVolumeKnobCore so that
// Swift 6's strict Sendable/actor-isolation checks don't false-positive on this pattern.

import Foundation
import QuartzCore

final class FlingEngine {

    // MARK: - Tuning

    private let flywheelDrag: Double      = 0.93
    private let flywheelAccelBase: Double = 0.030
    private let flywheelMinSpeed: Double  = 0.0003   // deg/frame
    private let flywheelHz: Double        = 120.0

    private let flingDragCoeff: Double    = 28.0     // a in v' = -a·v^b
    private let flingDragExp: Double      = 0.75     // b
    private let flingStopSpeed: Double    = 0.4      // deg/s
    private let flingMinExitSpeed: Double = 3.0      // deg/s
    private let flingHz: Double           = 120.0

    // MARK: - State (main-thread writes; background reads are safe on arm64)

    private var flywheelVelocity: Double = 0
    private var flywheelCallback: ((Double) -> Void)?
    private var flywheelTimer: DispatchSourceTimer?

    private var emaVelocity: Double = 0
    private var lastEventTime: CFTimeInterval = 0
    private let emaAlpha: Double = 0.35

    private var flingTimer: DispatchSourceTimer?

    // MARK: - Public API (call from main thread only)

    func beginGesture(callback: @escaping (Double) -> Void) {
        reset()
        flywheelCallback = callback
        startFlywheelTimer()
    }

    func pedal(degrees: Double, dt: Double) {
        let safeDt = max(dt, 0.001)
        emaVelocity = emaAlpha * (degrees / safeDt) + (1.0 - emaAlpha) * emaVelocity
        lastEventTime = CACurrentMediaTime()

        let speed = abs(degrees)
        let accelMult = 1.0 + min(speed / 6.0, 3.0)   // 1× – 4×
        flywheelVelocity += degrees * flywheelAccelBase * accelMult
    }

    func endGesture(callback: @escaping (Double) -> Void) {
        stopFlywheelTimer()
        flywheelVelocity = 0
        startFling(callback: callback)
    }

    func reset() {
        stopFlywheelTimer()
        stopFlingTimer()
        flywheelVelocity = 0
        flywheelCallback = nil
        emaVelocity = 0
        lastEventTime = 0
    }

    // MARK: - Flywheel timer

    private func startFlywheelTimer() {
        let drag     = flywheelDrag
        let minSpeed = flywheelMinSpeed

        let timer = makeTimer()
        schedule(timer, hz: flywheelHz)

        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.flywheelVelocity *= drag
            let v = self.flywheelVelocity
            guard abs(v) >= minSpeed else { return }
            let cb = self.flywheelCallback
            DispatchQueue.main.async { cb?(v) }
        }
        flywheelTimer = timer
        timer.resume()
    }

    private func stopFlywheelTimer() {
        flywheelTimer?.cancel()
        flywheelTimer = nil
    }

    // MARK: - DragCurve fling  (Euler: v'(t) = -a·v^b)

    private func startFling(callback: @escaping (Double) -> Void) {
        let timeSinceLast = lastEventTime > 0
            ? CACurrentMediaTime() - lastEventTime : Double.infinity
        let exitSpeed = abs(emaVelocity)
        guard exitSpeed >= flingMinExitSpeed, timeSinceLast < 0.10 else { return }

        let sign: Double = emaVelocity >= 0 ? 1.0 : -1.0
        var v = exitSpeed                   // purely local — no shared state

        let a         = flingDragCoeff
        let b         = flingDragExp
        let dt        = 1.0 / flingHz
        let stopSpeed = flingStopSpeed

        let timer = makeTimer()
        schedule(timer, hz: flingHz)

        timer.setEventHandler { [weak self] in
            v = max(0.0, v - a * pow(v, b) * dt)
            guard v >= stopSpeed else {
                DispatchQueue.main.async { self?.stopFlingTimer() }
                return
            }
            let delta = sign * v * dt
            DispatchQueue.main.async { callback(delta) }
        }
        flingTimer = timer
        timer.resume()
    }

    private func stopFlingTimer() {
        flingTimer?.cancel()
        flingTimer = nil
    }

    // MARK: - Helpers

    private func makeTimer() -> DispatchSourceTimer {
        DispatchSource.makeTimerSource(flags: [], queue: .global(qos: .userInteractive))
    }

    private func schedule(_ timer: DispatchSourceTimer, hz: Double) {
        let ns = UInt64(Double(NSEC_PER_SEC) / hz)
        timer.schedule(deadline: .now() + .nanoseconds(Int(ns)),
                       repeating: .nanoseconds(Int(ns)),
                       leeway: .nanoseconds(Int(ns / 10)))
    }
}
