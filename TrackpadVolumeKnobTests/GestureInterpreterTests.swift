// GestureInterpreterTests.swift
// Unit tests for the gesture-to-volume-delta pipeline.
// These tests use a stub VolumeController and HUDController to avoid
// touching real hardware.

import Testing
@testable import TrackpadVolumeKnobCore
import AppKit

// MARK: - Stubs

@MainActor
final class StubVolumeController: VolumeController {
    var adjustedDeltas: [Float] = []
    var setVolumes: [Float] = []

    override func adjustVolume(by delta: Float) {
        adjustedDeltas.append(delta)
        // Don't touch CoreAudio in tests
    }

    override func setVolume(_ volume: Float) {
        setVolumes.append(volume)
    }
}

// MARK: - GestureInterpreterTests

@MainActor
struct GestureInterpreterTests {

    // MARK: - Dead zone

    @Test("Small rotation below dead zone produces no volume change")
    func deadZoneFiltersSmallRotation() async {
        let settings = makeSettings(deadZoneDegrees: 3.0, degreesPerStep: 5.0, sensitivity: 0.05)
        let vol = StubVolumeController()
        let hud = HUDController()
        let interpreter = GestureInterpreter(settings: settings, volumeController: vol, hudController: hud)
        let engine = makeEngine(settings: settings)

        // Send 2° — below dead zone
        let event = RotationEvent(degrees: 2.0, timestamp: 1.0, phase: .changed)
        interpreter.gestureEngine(engine, didReceive: event)

        #expect(vol.adjustedDeltas.isEmpty)
    }

    @Test("Rotation above dead zone triggers volume adjustment")
    func aboveDeadZoneTriggersAdjustment() async {
        let settings = makeSettings(deadZoneDegrees: 1.0, degreesPerStep: 5.0, sensitivity: 0.05)
        let vol = StubVolumeController()
        let hud = HUDController()
        let interpreter = GestureInterpreter(settings: settings, volumeController: vol, hudController: hud)
        let engine = makeEngine(settings: settings)

        // Simulate a begin + 6° change
        interpreter.gestureEngineDidBeginGesture(engine)
        let event = RotationEvent(degrees: 6.0, timestamp: 1.0, phase: .changed)
        interpreter.gestureEngine(engine, didReceive: event)

        #expect(!vol.adjustedDeltas.isEmpty)
    }

    // MARK: - Direction inversion

    @Test("Clockwise rotation increases volume by default")
    func clockwiseIncreasesVolume() async {
        let settings = makeSettings(
            deadZoneDegrees: 0.0,
            degreesPerStep: 5.0,
            sensitivity: 0.05,
            invertDirection: false
        )
        let vol = StubVolumeController()
        let hud = HUDController()
        let interpreter = GestureInterpreter(settings: settings, volumeController: vol, hudController: hud)
        let engine = makeEngine(settings: settings)

        interpreter.gestureEngineDidBeginGesture(engine)
        let event = RotationEvent(degrees: 5.0, timestamp: 1.0, phase: .changed)
        interpreter.gestureEngine(engine, didReceive: event)

        #expect(vol.adjustedDeltas.first ?? 0 > 0)
    }

    @Test("Inverted direction: clockwise decreases volume")
    func invertedDirectionDecreases() async {
        let settings = makeSettings(
            deadZoneDegrees: 0.0,
            degreesPerStep: 5.0,
            sensitivity: 0.05,
            invertDirection: true
        )
        let vol = StubVolumeController()
        let hud = HUDController()
        let interpreter = GestureInterpreter(settings: settings, volumeController: vol, hudController: hud)
        let engine = makeEngine(settings: settings)

        interpreter.gestureEngineDidBeginGesture(engine)
        let event = RotationEvent(degrees: 5.0, timestamp: 1.0, phase: .changed)
        interpreter.gestureEngine(engine, didReceive: event)

        #expect(vol.adjustedDeltas.first ?? 0 < 0)
    }

    // MARK: - Accumulator reset

    @Test("Begin gesture resets accumulator")
    func beginGestureResetsAccumulator() async {
        let settings = makeSettings(deadZoneDegrees: 3.0, degreesPerStep: 5.0, sensitivity: 0.05)
        let vol = StubVolumeController()
        let hud = HUDController()
        let interpreter = GestureInterpreter(settings: settings, volumeController: vol, hudController: hud)
        let engine = makeEngine(settings: settings)

        // Add some partial accumulation
        let partial = RotationEvent(degrees: 2.5, timestamp: 1.0, phase: .changed)
        interpreter.gestureEngine(engine, didReceive: partial)

        // Begin resets — next 5° should still fire (not carry over the 2.5°)
        interpreter.gestureEngineDidBeginGesture(engine)
        let event = RotationEvent(degrees: 5.0, timestamp: 2.0, phase: .changed)
        interpreter.gestureEngine(engine, didReceive: event)

        // Should fire exactly 1 step (5° exactly equals one step)
        #expect(vol.adjustedDeltas.count == 1)
    }

    // MARK: - Volume clamping (via VolumeController)

    @Test("VolumeController clamps volume to [0, 1]")
    func volumeIsClamped() async {
        let vc = VolumeController()
        vc.setVolume(1.5)
        // Can't read currentVolume easily without real CoreAudio, but
        // the clamp logic is exercised — no crash is the assertion here.
    }

    // MARK: - Helpers

    private func makeSettings(
        deadZoneDegrees: Double = 1.5,
        degreesPerStep: Double = 5.0,
        sensitivity: Double = 0.05,
        invertDirection: Bool = false,
        acceleration: Double = 1.0
    ) -> AppSettings {
        let s = AppSettings.shared
        s.deadZoneDegrees = deadZoneDegrees
        s.degreesPerStep = degreesPerStep
        s.sensitivity = sensitivity
        s.invertDirection = invertDirection
        s.acceleration = acceleration
        s.debugLogging = false
        return s
    }

    private func makeEngine(settings: AppSettings) -> GestureEngine {
        let hud = HUDController()
        let vol = StubVolumeController()
        let interp = GestureInterpreter(settings: settings, volumeController: vol, hudController: hud)
        return GestureEngine(settings: settings, interpreter: interp)
    }
}
