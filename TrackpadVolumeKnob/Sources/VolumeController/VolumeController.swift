// VolumeController.swift
// Sets system volume via CoreAudio and triggers the native macOS HUD
// by posting NX system-defined media key events (same as pressing F11/F12).
import AppKit
import CoreAudio
import Foundation

@MainActor
open class VolumeController {

    // MARK: - Public

    public private(set) var currentVolume: Float = 0.5

    // NX key identifiers for the media keys
    private static let NX_KEYTYPE_SOUND_UP:   Int = 0
    private static let NX_KEYTYPE_SOUND_DOWN: Int = 1

    public init() {
        currentVolume = getCoreAudioVolume() ?? 0.5
    }

    /// Adjust volume by a signed scalar delta [0..1].
    /// Writes CoreAudio silently — no media key, no HUD snap.
    /// Call showHUD() once at gesture end to surface the native HUD.
    open func adjustVolume(by delta: Float) {
        guard delta != 0 else { return }
        let newVolume = (currentVolume + delta).clamped(to: 0.0...1.0)
        setCoreAudioVolume(newVolume)
    }

    /// Post one media key in the right direction so the native HUD appears.
    /// Call once at gesture end (or fling end), not on every event.
    open func showHUD(increasing: Bool) {
        postMediaKey(increasing ? Self.NX_KEYTYPE_SOUND_UP : Self.NX_KEYTYPE_SOUND_DOWN)
    }

    open func setVolume(_ volume: Float) {
        setCoreAudioVolume(volume.clamped(to: 0.0...1.0))
    }

    // MARK: - Native HUD trigger

    /// Posts a single NX_SYSDEFINED media key press+release.
    /// This is identical to a physical F11/F12 keypress and causes the
    /// native macOS volume HUD to appear.
    private func postMediaKey(_ keyCode: Int) {
        // Build data1: high 16 bits = key code, bits 8-11 = event flags
        // 0xa = NX_KEYDOWN, 0xb = NX_KEYUP  (from <IOKit/hidsystem/ev_keymap.h>)
        func send(flags: Int) {
            let data1 = (keyCode << 16) | (flags << 8)
            guard let e = NSEvent.otherEvent(
                with: NSEvent.EventType.systemDefined,
                location: NSPoint.zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: 0),
                timestamp: 0,
                windowNumber: 0,
                context: nil as NSGraphicsContext?,
                subtype: Int16(8),   // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                data1: data1,
                data2: -1
            ) else { return }
            e.cgEvent?.post(tap: CGEventTapLocation.cghidEventTap)
        }

        send(flags: 0xa) // key down
        send(flags: 0xb) // key up
    }

    // MARK: - CoreAudio

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private func getCoreAudioVolume() -> Float? {
        guard let deviceID = defaultOutputDeviceID() else { return nil }
        for channel: UInt32 in [0, 1, 2] {
            var vol = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel
            )
            if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &vol) == noErr {
                return vol
            }
        }
        return nil
    }

    private func setCoreAudioVolume(_ volume: Float) {
        guard let deviceID = defaultOutputDeviceID() else { return }
        var scalar = Float32(volume)
        let size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &scalar) != noErr {
            for channel: UInt32 in [1, 2] {
                var addr = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: channel
                )
                AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &scalar)
            }
        }
        currentVolume = volume
        Logger.debug("VolumeController: set to \(String(format: "%.3f", volume))")
    }
}

// MARK: - Clamp

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
