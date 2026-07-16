# Mac Trackpad Fix

A lightweight, native macOS menu bar app that unlocks your trackpad as a system control surface — rotate two fingers to change volume or brightness, pinch to do the same. Just like turning a physical knob.

> Rotate clockwise → Volume up  
> Rotate counter-clockwise → Volume down  
> Spread fingers → Brightness up  
> Pinch fingers → Brightness down

Inspired by [Mac Mouse Fix](https://macmousefix.com). Built with Swift 6, SwiftUI, and AppKit. No Electron. No React Native. No subscriptions.

---

## Features

- **Two-finger rotation** on any MacBook or Magic Trackpad
- **Pinch gesture** for brightness or volume control
- **Floating HUD** near your cursor showing a live arc + percentage
- **Smooth acceleration** — slow rotations are precise, fast rotations jump further
- **Adjustable sensitivity**, dead zone, and acceleration curve
- **Fallback mode** — hold a modifier key (Option, Control, Fn, ⌘) to activate
- **Launch at login** via `SMAppService`
- **Works with all output devices**: built-in speakers, AirPods, Bluetooth, USB DACs
- **External display brightness** via DDC
- **< 50 MB RAM, < 1% CPU idle**, < 20 ms gesture latency
- MIT licensed, fully open source

---

## Architecture

```
Trackpad Hardware
      │
      ▼
 macOS Gesture Engine
(OS-level rotation/pinch recognition)
      │  NSEvent (.rotate / .magnify)
      ▼
┌─────────────────────┐
│    GestureEngine    │  Observes global NSEvent monitor
│                     │  Applies fallback-mode modifier filtering
└──────────┬──────────┘
           │  RotationEvent / PinchEvent
           ▼
┌─────────────────────┐
│ GestureInterpreter  │  Dead zone · Sensitivity · Acceleration
│                     │  Direction inversion · Step accumulation
└──────┬──────┬───────┘
       │      │
       │      └─────────────────────────┐
       │  volume/brightness delta       │ level
       ▼                                ▼
┌─────────────────┐          ┌──────────────────┐
│VolumeController │          │   HUDController  │
│BrightnessCtrl   │          │  (SwiftUI HUD)   │
└─────────────────┘          └──────────────────┘
```

### Module overview

| Module | Responsibility |
|---|---|
| `GestureEngine` | Owns the `NSEvent` global monitor; emits rotation and pinch events |
| `GestureInterpreter` | Converts raw degrees/magnitude → steps with smoothing |
| `VolumeController` | CoreAudio wrapper; reads/writes default output volume |
| `BrightnessController` | Built-in and DDC brightness control |
| `HUDController` | Manages the floating NSWindow overlay lifecycle |
| `HUDView` | SwiftUI arc + icon + percentage indicator |
| `AppSettings` | `UserDefaults`-backed `@Observable` preferences store |
| `PermissionsManager` | Checks/requests Accessibility permission |
| `LaunchAtLoginManager` | `SMAppService` wrapper for launch-at-login |
| `Logger` | `os.Logger` wrapper with debug gating |

---

## Requirements

- macOS 14 Sonoma or later
- Xcode 16+ (Swift 6 toolchain)
- A MacBook trackpad or Apple Magic Trackpad

---

## Build Instructions

### Using Xcode

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/mac-trackpad-fix.git
   cd mac-trackpad-fix
   ```

2. Open the Swift Package in Xcode:
   ```bash
   open Package.swift
   ```

3. Select the `MacTrackpadFix` scheme and press **⌘R** to build and run.

### Using Swift Package Manager (CLI)

```bash
# Debug build
swift build

# Release build (smaller binary, optimised)
swift build -c release

# Run directly
swift run MacTrackpadFix
```

> **Note:** The app requires Accessibility permission to monitor global gestures.  
> On first launch an onboarding screen guides you through granting it in  
> System Settings › Privacy & Security › Accessibility.

### Create a distributable .app bundle

```bash
# Build release binary
swift build -c release

# Assemble the .app structure
mkdir -p MacTrackpadFix.app/Contents/MacOS
mkdir -p MacTrackpadFix.app/Contents/Resources

cp .build/release/MacTrackpadFix MacTrackpadFix.app/Contents/MacOS/
cp TrackpadVolumeKnob/Resources/Info.plist MacTrackpadFix.app/Contents/

# (optional) code-sign for Gatekeeper
codesign --deep --force --sign "Developer ID Application: Your Name (TEAMID)" \
  MacTrackpadFix.app
```

### Run tests

```bash
swift test
```

### Lint

```bash
# Install SwiftLint if needed
brew install swiftlint

swiftlint lint
```

---

## Permissions

Mac Trackpad Fix requests **one** permission:

| Permission | Why |
|---|---|
| **Accessibility** (Privacy & Security › Accessibility) | Required by `NSEvent.addGlobalMonitorForEventsMatchingMask` to receive gesture events sent to other applications |

No microphone, camera, location, contacts, or network access is requested or used.

---

## Settings

| Setting | Default | Description |
|---|---|---|
| Sensitivity | 5% | Volume/brightness change per step |
| Degrees per step | 5° | How much rotation equals one step |
| Dead zone | 1.5° | Minimum rotation before anything happens |
| Acceleration | 2.0× | Multiplier applied to fast rotations |
| Invert direction | Off | Swap clockwise ↔ counter-clockwise |
| Fallback mode | Off | Require a modifier key while rotating |
| Pinch gesture | On | Enable pinch for brightness/volume |
| Launch at login | Off | Start automatically on user login |

---

## License

MIT — see [LICENSE](LICENSE).
