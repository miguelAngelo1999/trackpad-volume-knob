// FlingEngine.swift
//
// Provides post-lift fling (momentum coast) for rotation gestures.
//
// Design:
//   • During an active gesture there is NO background timer — deltas are applied
//     directly from trackpad events in GestureInterpreter. This eliminates the
//     DispatchQueue.main.async pile-up that caused volume jitter.
//
//   • After fingers lift (endGesture), a CVDisplayLink runs the DragCurve Euler
//     integration on a background thread, signals a DispatchSourceUserDataAdd on
//     the main queue, and the main-queue handler reads the accumulated delta once
//     per drain cycle. DispatchSourceUserDataAdd coalesces signals automatically,
//     so no matter how fast CVDisplayLink fires, the main thread sees exactly one
//     handler call per runloop turn — no racing writes.
//
//   • EMA exit-velocity is tracked from the last few gesture events to decide
//     whether and how fast to fling after lift.

import CoreVideo
import Foundation
import QuartzCore

final class FlingEngine {

    // MARK: - Tuning

    /// Minimum exit speed (deg/s) to trigger a fling at all.
    /// Low enough to catch short fast flicks (2-3 events).
    private let flingMinExitSpeed: Double = 2.0
    /// DragCurve: v'(t) = -a · v^b
    private let flingDragCoeff: Double    = 30.0
    private let flingDragExp: Double      = 0.72
    /// Speed (deg/s) at which we consider the fling done
    private let flingStopSpeed: Double    = 0.5
    /// Scale applied to exit velocity
    private let flingVelocityScale: Double = 0.9

    // MARK: - EMA velocity tracking (updated by GestureInterpreter during gesture)

    private var emaVelocity: Double = 0
    private var peakVelocity: Double = 0       // max instantaneous speed seen this gesture
    private var lastEventTime: CFTimeInterval = 0
    private let emaAlpha: Double = 0.55        // higher alpha = more responsive to latest events

    // MARK: - Fling state

    private var flingVelocity: Double = 0      // current speed, deg/s — written on CVDisplayLink thread, read on main
    private var flingSign: Double = 1.0
    private var displayLink: CVDisplayLink?
    private var flingSource: DispatchSourceUserDataAdd?
    private var flingCallback: ((Double) -> Void)?

    // MARK: - Public API (call from main thread)

    /// Reset everything — call at gesture begin.
    func reset() {
        stopFling()
        emaVelocity = 0
        peakVelocity = 0
        lastEventTime = 0
    }

    /// Track a gesture event for EMA exit-velocity. Call on every rotation event.
    func track(degrees: Double, dt: Double) {
        let safeDt = max(dt, 0.001)
        let instant = abs(degrees) / safeDt     // deg/s (unsigned for peak tracking)
        let signed  = degrees / safeDt

        // EMA for smooth exit velocity
        emaVelocity = emaAlpha * signed + (1.0 - emaAlpha) * emaVelocity

        // Peak: decays toward current EMA so an old burst doesn't dominate forever,
        // but a fast flick's maximum speed is preserved for the fling decision.
        peakVelocity = max(peakVelocity * 0.85, instant)

        lastEventTime = CACurrentMediaTime()
    }

    /// Start post-lift fling. callback receives signed deg/s · dt deltas on the main thread.
    func startFling(callback: @escaping (Double) -> Void) {
        stopFling()

        let timeSinceLast = lastEventTime > 0
            ? CACurrentMediaTime() - lastEventTime : Double.infinity

        // Use peak velocity for the fling speed decision — it catches short fast
        // flicks that EMA underestimates (only 2-3 events before lift-off).
        // EMA provides the sign (direction).
        let exitSpeed = peakVelocity * flingVelocityScale
        let sign = emaVelocity >= 0 ? 1.0 : -1.0

        // Widen the time window to 200ms — gesture .ended can arrive well after
        // the last rotation event on a short fast flick.
        guard exitSpeed >= flingMinExitSpeed, timeSinceLast < 0.20 else { return }

        flingSign     = sign
        flingVelocity = exitSpeed
        flingCallback = callback

        // DispatchSourceUserDataAdd on the main queue — coalesces signals so we
        // get exactly one handler call per main-queue drain, even if CVDisplayLink
        // fires multiple times before the main thread wakes up.
        let source = DispatchSource.makeUserDataAddSource(queue: .main)
        flingSource = source

        let a         = flingDragCoeff
        let b         = flingDragExp
        let stopSpeed = flingStopSpeed

        source.setEventHandler { [weak self] in
            guard let self, let cb = self.flingCallback else { return }

            // Each coalesced signal represents one CVDisplayLink tick at ~dt.
            // data() gives the number of accumulated ticks; use it to step the
            // integrator the right number of times.
            let ticks = source.data             // coalesced tick count
            let dt    = 1.0 / 120.0

            var v = self.flingVelocity
            var totalDelta = 0.0

            for _ in 0..<max(1, ticks) {
                v = max(0.0, v - a * pow(v, b) * dt)
                totalDelta += v * dt
                if v < stopSpeed { break }
            }

            self.flingVelocity = v

            if v < stopSpeed {
                self.stopFling()
                return
            }

            cb(self.flingSign * totalDelta)
        }
        source.resume()

        // CVDisplayLink fires on its own high-priority thread — we just signal the source.
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { stopFling(); return }

        let sourceRef = Unmanaged.passRetained(source)

        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, ctx -> CVReturn in
            guard let ctx else { return kCVReturnSuccess }
            let src = Unmanaged<DispatchSourceUserDataAdd>.fromOpaque(ctx).takeUnretainedValue()
            src.add(data: 1)
            return kCVReturnSuccess
        }, sourceRef.toOpaque())

        CVDisplayLinkStart(link)
        displayLink = link

        // Balance the retain when the source cancels
        source.setCancelHandler {
            sourceRef.release()
        }
    }

    // MARK: - Private

    private func stopFling() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
        flingSource?.cancel()
        flingSource = nil
        flingCallback = nil
        flingVelocity = 0
    }
}
