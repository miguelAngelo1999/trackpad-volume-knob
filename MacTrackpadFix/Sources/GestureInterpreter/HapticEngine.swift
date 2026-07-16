// HapticEngine.swift
// Trackpad Force Touch haptic feedback during volume/brightness changes.
//
// Volume and brightness use different pattern mappings so they feel
// physically distinct — volume feels like a firm notched knob, brightness
// feels like a softer dimmer slider.
//
// Volume patterns (firm):
//   light  → .generic
//   medium → .alignment
//   strong → .levelChange
//
// Brightness patterns (softer, one step down):
//   light  → .generic  (same — already minimal)
//   medium → .generic
//   strong → .alignment
//
// Notch logic: fires a .levelChange bump (volume) or .alignment bump
// (brightness) whenever the value crosses a 10% boundary, giving tactile
// confirmation at round numbers regardless of chosen level.
//
// Rate-limiting: min interval between ticks prevents actuator buzz.

import AppKit

@MainActor
final class HapticEngine {

    // MARK: - Tuning

    private let minTickInterval: TimeInterval = 0.035   // ~28 ticks/s max
    private let notchStep: Float = 0.10

    // MARK: - Separate state per target (volume/brightness rotate independently)

    private var volumeLastTick: TimeInterval = 0
    private var volumeLastValue: Float = -1

    private var brightnessLastTick: TimeInterval = 0
    private var brightnessLastValue: Float = -1

    private let performer: NSHapticFeedbackPerformer? =
        NSHapticFeedbackManager.defaultPerformer

    // MARK: - Public API

    /// Call on every value change. target distinguishes volume from brightness.
    func feedback(value: Float, delta: Float, target: GestureTarget, level: HapticLevel) {
        guard level != .off else { return }
        guard abs(delta) > 0.0001 else { return }
        guard let performer else { return }

        let now = CACurrentMediaTime()
        let isVolume = (target == .volume)

        var lastValue  = isVolume ? volumeLastValue       : brightnessLastValue
        var lastTick   = isVolume ? volumeLastTick        : brightnessLastTick

        defer {
            if isVolume {
                volumeLastValue = value
                volumeLastTick  = lastTick
            } else {
                brightnessLastValue = value
                brightnessLastTick  = lastTick
            }
        }

        // 1. Notch check — fires regardless of rate limit
        let notchIdx     = floor(value    / notchStep)
        let lastNotchIdx = lastValue < 0 ? notchIdx : floor(lastValue / notchStep)

        if lastValue >= 0 && notchIdx != lastNotchIdx {
            // Volume: firm bump; Brightness: softer snap
            let notchPattern: NSHapticFeedbackManager.FeedbackPattern =
                isVolume ? .levelChange : .alignment
            performer.perform(notchPattern, performanceTime: .now)
            lastTick = now
            return
        }

        // 2. Regular tick — rate-limited
        guard now - lastTick >= minTickInterval else { return }
        lastTick = now

        let pattern: NSHapticFeedbackManager.FeedbackPattern
        if isVolume {
            // Volume: firm escalating patterns
            switch level {
            case .off:    return
            case .light:  pattern = .generic
            case .medium: pattern = .alignment
            case .strong: pattern = .levelChange
            }
        } else {
            // Brightness: softer — shifted one step down
            switch level {
            case .off:    return
            case .light:  pattern = .generic
            case .medium: pattern = .generic
            case .strong: pattern = .alignment
            }
        }

        performer.perform(pattern, performanceTime: .now)
    }

    func reset() {
        volumeLastValue     = -1
        volumeLastTick      = 0
        brightnessLastValue = -1
        brightnessLastTick  = 0
    }
}
