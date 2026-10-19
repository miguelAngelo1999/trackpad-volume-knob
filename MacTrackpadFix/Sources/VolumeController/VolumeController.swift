// VolumeController.swift
// Sets system volume via CoreAudio and shows the native macOS OSD HUD
// via OSD.framework (same mechanism as BrightnessController) — NO media key.
// Using postMediaKey would snap the volume to the nearest 6.25% step
// after every gesture, making smooth volume changes feel stepped.
import AppKit
import CoreAudio
import Foundation

@MainActor
open class VolumeController {

    // MARK: - Public

    public private(set) var currentVolume: Float = 0.5

    // OSD.framework — loaded lazily, same approach as BrightnessController
    private typealias ShowImageFn = @convention(c) (
        AnyObject, Selector,
        Int64,   // imageID: 3=volume, 4=muted
        UInt32,  // displayID
        UInt32,  // priority
        UInt32,  // msecUntilFade
        UInt32,  // filledChiclets
        UInt32,  // totalChiclets
        ObjCBool // locked
    ) -> Void

    public init() {
        currentVolume = getCoreAudioVolume() ?? 0.5
        dlopen("/System/Library/PrivateFrameworks/OSD.framework/OSD", RTLD_LAZY)
    }

    /// Adjust volume by a signed scalar delta [0..1].
    /// Writes CoreAudio silently — no media key, no HUD snap.
    open func adjustVolume(by delta: Float) {
        guard delta != 0 else { return }
        let newVolume = (currentVolume + delta).clamped(to: 0.0...1.0)
        setCoreAudioVolume(newVolume)
    }

    /// Show the native macOS volume OSD via OSD.framework.
    /// Does NOT post a media key — so volume is never snapped to a 6.25% step.
    open func showHUD(increasing: Bool) {
        showOSDVolume(volume: currentVolume)
    }

    open func setVolume(_ volume: Float) {
        setCoreAudioVolume(volume.clamped(to: 0.0...1.0))
    }

    // MARK: - OSD HUD (no media key = no snap)

    private func showOSDVolume(volume: Float) {
        guard let cls = NSClassFromString("OSDManager") as? NSObjectProtocol.Type else { return }
        guard let mgr = (cls as AnyObject).perform(Selector("sharedManager"))?.takeUnretainedValue()
              else { return }

        let sel = NSSelectorFromString(
            "showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:")
        guard (mgr as AnyObject).responds(to: sel) else { return }

        let imp = (mgr as AnyObject).method(for: sel)
        let fn  = unsafeBitCast(imp, to: ShowImageFn.self)

        let imageID: Int64 = volume <= 0 ? 4 : 3   // 4=muted, 3=volume
        let filled  = UInt32(max(0, min(16, Int(volume * 16 + 0.5))))
        fn(mgr as AnyObject, sel,
           imageID,
           CGMainDisplayID(),
           0x1F4,   // priority
           1000,    // ms until fade
           filled,
           16,
           false)
    }
        // Build data1: high 16 bits = key code, bits 8-11 = event flags

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
