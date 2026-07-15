# TrackpadVolumeKnob

A lightweight, native macOS menu bar app that lets you control system volume by rotating two fingers on your trackpad — just like turning a physical volume knob.

> Rotate clockwise → Volume up  
> Rotate counter-clockwise → Volume down

Built with Swift 6, SwiftUI, and AppKit. No Electron. No React Native. No subscriptions.

---

## Features

- **Two-finger rotation** on any MacBook or Magic Trackpad
- **Floating HUD** near your cursor showing a live volume arc + percentage
- **Smooth acceleration** — slow rotations are precise, fast rotations jump further
- **Adjustable sensitivity**, dead zone, and acceleration curve
- **Fallback mode** — hold a modifier key (Option, Control, Fn, ⌘) to activate
- **Launch at login** via `SMAppService`
- **Works with all output devices**: built-in speakers, AirPods, Bluetooth, USB DACs
- **< 50 MB RAM, < 1% CPU idle**, < 20 ms gesture latency
- MIT licensed, fully open source

---

## Architecture

```
Trackpad Hardware
      │
      ▼
 macOS Gesture Engine
(OS-level rotation recognition)
      │  NSEvent (.rotate)
      ▼
┌─────────────────────┐
│    GestureEngine    │  Observes global NSEvent rotation monitor
│                     │  Applies fallback-mode modifier filtering
└──────────┬──────────┘
           │  RotationEvent (degrees, timestamp, phase)
           ▼
┌─────────────────────┐
│ GestureInterpreter  │  Dead zone · Sensitivity · Acceleration
│                     │  Direction inversion · Step accumulation
└──────┬──────┬───────┘
       │      │
       │      └─────────────────────────┐
       │  volume delta (Float)          │ volume level
       ▼                                ▼
┌─────────────────┐          ┌──────────────────┐
│ VolumeController│          │   HUDController  │
│   (CoreAudio)   │          │  (SwiftUI HUD)   │
└─────────────────┘          └──────────────────┘
       │
       ▼
  macOS Audio Output
(Built-in / AirPods / BT / USB)
```

### Module overview

| Module | Responsibility |
|---|---|
| `GestureEngine` | Owns the `NSEvent` global monitor; emits `RotationEvent` |
| `GestureInterpreter` | Converts raw degrees → volume steps with smoothing |
| `VolumeController` | CoreAudio wrapper; reads/writes default output volume |
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
   git clone https://github.com/yourusername/TrackpadVolumeKnob.git
   cd TrackpadVolumeKnob
   ```

2. Open the Swift Package in Xcode:
   ```bash
   open Package.swift
   ```

3. Select the `TrackpadVolumeKnob` scheme and press **⌘R** to build and run.

### Using Swift Package Manager (CLI)

```bash
# Debug build
swift build

# Release build (smaller binary, optimised)
swift build -c release

# Run directly
swift run TrackpadVolumeKnob
```

> **Note:** The app requires Accessibility permission to monitor global gestures.  
> On first launch an onboarding screen guides you through granting it in  
> System Settings › Privacy & Security › Accessibility.

### Create a distributable .app bundle

```bash
# Build release binary
swift build -c release

# Assemble the .app structure
mkdir -p TrackpadVolumeKnob.app/Contents/MacOS
mkdir -p TrackpadVolumeKnob.app/Contents/Resources

cp .build/release/TrackpadVolumeKnob TrackpadVolumeKnob.app/Contents/MacOS/
cp TrackpadVolumeKnob/Resources/Info.plist TrackpadVolumeKnob.app/Contents/

# (optional) code-sign for Gatekeeper
codesign --deep --force --sign "Developer ID Application: Your Name (TEAMID)" \
  TrackpadVolumeKnob.app
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

TrackpadVolumeKnob requests **one** permission:

| Permission | Why |
|---|---|
| **Accessibility** (Privacy & Security › Accessibility) | Required by `NSEvent.addGlobalMonitorForEventsMatchingMask` to receive gesture events sent to other applications |

No microphone, camera, location, contacts, or network access is requested or used.

---

## Settings

| Setting | Default | Description |
|---|---|---|
| Sensitivity | 5% | Volume change per step |
| Degrees per step | 5° | How much rotation equals one step |
| Dead zone | 1.5° | Minimum rotation before anything happens |
| Acceleration | 2.0× | Multiplier applied to fast rotations |
| Invert direction | Off | Swap clockwise ↔ counter-clockwise |
| Fallback mode | Off | Require a modifier key while rotating |
| Launch at login | Off | Start automatically on user login |

---

## Fallback Mode

If you prefer not to grant broad Accessibility access, or want intentional activation, enable **Fallback Mode** in Settings › Gestures. While active, the engine only responds to rotation while you hold the configured modifier key (Option by default).

---

## Future Roadmap

The architecture is intentionally modular so new gestures and actions can be added without touching existing code.

**Planned gestures:**
- Pinch → Brightness / Zoom
- Three-finger swipe → Media controls (previous / play-pause / next)
- Four-finger rotate → Custom shortcut

**Planned actions:**
- Display brightness (using `IOKit` display services)
- Keyboard backlight
- Custom shell script / AppleScript

**Advanced gesture engine:**
- Optional `MultitouchSupport.framework` mode for lower latency and no permission requirement
- Plugin system for community-contributed gesture→action mappings

---

## License

MIT — see [LICENSE](LICENSE).
