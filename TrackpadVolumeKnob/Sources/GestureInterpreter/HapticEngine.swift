// HapticEngine.swift
// Trackpad Force Touch haptic feedback during volume/brightness changes.
//
// NSHapticFeedbackManager patterns used:
//   .generic       — subtle tick, lowest weight (light level)
//   .alignment     — medium snap (medium level)
//   .levelChange   — stronger bump (strong level, and at 10% notches)
//
// Notch logic: fires a .levelChange bump whenever the value crosses a
// 10% boundary (0.1, 0.2, … 0.9) regardless of chosen level, as long
// as haptic is not off. This gives a physical "click" at round numbers.
//
// Rate-limiting: a minimum interval between ticks prevents the trackpad
// actuator from being overwhelmed on fast continuous rotation.

import AppKit

@MainActor
final class HapticEngine {

    // MARK: - Tuning

    /// Minimum seconds between regular ticks (light/medium/strong).
    /// At 120Hz rotation events this prevents the actuator from buzzing.
    private let minTickInterval: TimeInterval = 0.035   // ~28 ticks/s max

    /// Boundary granularity for notch bumps (every 10%).
    private let notchStep: Float = 0.10

    // MARK: - State

    private var lastTickTime: TimeInterval = 0
    private var lastNotchedValue: Float = -1   // -1 = not yet set

    private let performer: NSHapticFeedbackPerformer? = {
        NSHapticFeedbackManager.defaultPerformer
    }()

    // MARK: - Public API

    /// Call on every value change during a gesture.
    /// value: current volume/brightness in [0, 1]
    /// delta: signed change this tick (used to skip feedback on no-ops)
    /// level: user-chosen haptic intensity
    func feedback(value: Float, delta: Float, level: HapticLevel) {
        guard level != .off else { return }
        guard abs(delta) > 0.0001 else { return }
        guard let performer else { return }

        let now = CACurrentMediaTime()

        // 1. Notch check — fires regardless of tick rate limit
        let notchIndex = floor(value / notchStep)
        let lastNotchIndex = lastNotchedValue < 0 ? notchIndex : floor(lastNotchedValue / notchStep)
        if lastNotchedValue >= 0 && notchIndex != lastNotchIndex {
            performer.perform(.levelChange, performanceTime: .now)
            lastNotchedValue = value
            lastTickTime = now
            return
        }
        lastNotchedValue = value

        // 2. Regular tick — rate-limited
        guard now - lastTickTime >= minTickInterval else { return }
        lastTickTime = now

        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch level {
        case .off:    return
        case .light:  pattern = .generic
        case .medium: pattern = .alignment
        case .strong: pattern = .levelChange
        }

        performer.perform(pattern, performanceTime: .now)
    }

    /// Reset notch tracking at gesture begin so we don't fire a spurious
    /// notch bump on the very first event.
    func reset() {
        lastNotchedValue = -1
        lastTickTime = 0
    }
}
