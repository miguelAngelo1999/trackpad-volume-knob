# TrackpadVolumeKnob — Developer Guide

This document describes the full architecture, every module, all non-obvious design decisions, and the common pitfalls. If you're picking this up cold, read from top to bottom.

---

## Repository layout

```
mac-trackpad-fix/
├── Package.swift                        Swift package manifest
├── TrackpadVolumeKnob/
│   ├── App/                             Thin executable target (TrackpadVolumeKnobApp)
│   │   ├── main.swift                   NSApplicationMain entry point
│   │   └── AppDelegate.swift            Root coordinator / wiring
│   ├── Sources/                         Library target (TrackpadVolumeKnobCore)
│   │   ├── AppSettings.swift            All user preferences + exclusion list
│   │   ├── GestureEngine/
│   │   │   └── GestureEngine.swift      Input: NSEvent monitors + CGEventTap
│   │   ├── GestureInterpreter/
│   │   │   ├── GestureInterpreter.swift Raw degrees → volume/brightness delta
│   │   │   ├── FlingEngine.swift        Post-lift momentum (CVDisplayLink)
│   │   │   └── HapticEngine.swift       Force Touch feedback
│   │   ├── VolumeController/
│   │   │   └── VolumeController.swift   CoreAudio read/write + HUD trigger
│   │   ├── BrightnessController/
│   │   │   ├── BrightnessController.swift  DisplayServices + OSD + gamma
│   │   │   └── BrightnessControllerDDC.swift  DDC over IOAVService / I2C
│   │   ├── HUD/
│   │   │   ├── HUDController.swift      Floating NSWindow lifecycle
│   │   │   └── HUDView.swift            SwiftUI arc + icon + percentage
│   │   ├── Permissions/
│   │   │   ├── PermissionsManager.swift AXIsProcessTrusted + tccutil reset
│   │   │   └── OnboardingView.swift     First-run / re-authorization UI
│   │   ├── Settings/
│   │   │   └── SettingsView.swift       5-tab preferences window
│   │   └── Utilities/
│   │       ├── LaunchAtLoginManager.swift  SMAppService wrapper
│   │       └── Logger.swift             os.Logger wrapper
│   ├── Resources/
│   │   ├── Info.plist
│   │   └── TrackpadVolumeKnob.entitlements
├── TrackpadVolumeKnobTests/             XCTest target
├── GestureTest/
│   └── main.swift                       Standalone NSEvent monitor test tool
├── scripts/
│   ├── deploy.sh                        Build + sign + install
│   ├── reset_accessibility.sh           tccutil reset helper
│   └── check_ax.swift                   AXIsProcessTrusted probe
└── docs/
    ├── USER_GUIDE.md
    └── DEVELOPER_GUIDE.md  ← you are here
```

---

## Build system

**Swift Package Manager, swift-tools-version 6.0, macOS 14 minimum.**

Three targets in `Package.swift`:

| Target | Type | Swift mode | Notes |
|---|---|---|---|
| `TrackpadVolumeKnobApp` | Executable | Swift 6 | Entry point only, imports Core |
| `TrackpadVolumeKnobCore` | Library | Swift 5 | All logic. Swift 5 mode intentional — see Concurrency section |
| `GestureTest` | Executable | Swift 6 | Dev tool, not shipped |

### Why Swift 5 mode for the core target?

`FlingEngine` uses `DispatchSourceTimer` + `DispatchQueue.main.async` for its CVDisplayLink-based momentum loop. Swift 6's strict actor-isolation checker rejects this pattern with `SendingRisksDataRace` errors even though the threading is provably safe (background timer writes only to local captured variables, all controller calls hop to main via `DispatchQueue.main.async`). Switching the core target to `.swiftLanguageMode(.v5)` silences the false positives while keeping the Swift 6 toolchain for everything else.

If you want to upgrade to full Swift 6 concurrency, the correct fix is to mark the timer-captured variables `nonisolated(unsafe)` and change the callback type to `@Sendable`. That's more invasive but cleaner long-term.

### Development build and deploy

```bash
# Build + sign + install + launch
./scripts/deploy.sh

# Build only
swift build

# Run tests
swift test

# Gesture event probe (no full app needed)
swift build --product GestureTest
.build/debug/GestureTest
```

`deploy.sh` ad-hoc signs the binary with `codesign --preserve-metadata=identifier` after each copy. This keeps the TCC trust entry valid across binary replacements because macOS uses the bundle identifier as the signing identity for ad-hoc signed apps, not a hash of the binary.

---

## Data flow

```
Two-finger rotate on trackpad
         │
         │  NSEvent .rotate (phase: began/changed/ended)
         │  CGEventType 29 via CGEventTap (fallback)
         ▼
┌────────────────────┐
│   GestureEngine    │  handle(event:)
│                    │  • App exclusion check (NSWorkspace.frontmostApplication)
│                    │  • Fallback modifier check
│                    │  • Emits: gestureEngineDidBeginGesture
│                    │          gestureEngine(_:didReceive:RotationEvent)
│                    │          gestureEngineDidEndGesture
└─────────┬──────────┘
          │  RotationEvent(degrees, timestamp, phase)
          ▼
┌────────────────────────┐
│  GestureInterpreter    │
│                        │  on begin:  lockedTarget = resolvedTarget()
│                        │             flingEngine.reset()
│                        │             hapticEngine.reset()
│                        │
│                        │  on event:  dead zone accumulator
│                        │             flingEngine.track(degrees, dt)
│                        │             applyDelta(degrees, lockedTarget)
│                        │
│                        │  on end:    showHUD (volume only)
│                        │             flingEngine.startFling(callback)
└────┬───────────────────┘
     │  Float delta [−1…1]
     ├──────────────────────────────────────┐
     ▼                                      ▼
┌──────────────────┐              ┌──────────────────────┐
│ VolumeController │              │ BrightnessController  │
│ CoreAudio write  │              │ DisplayServices /     │
│ NX key for HUD   │              │ DDC / software gamma  │
└──────────────────┘              └──────────────────────┘
     │  currentVolume                       │  currentBrightness()
     └──────────────┬───────────────────────┘
                    ▼
           ┌─────────────────┐
           │   HapticEngine  │
           │ per-target state│
           │ notch detection │
           └─────────────────┘

FlingEngine (post-lift only):
  CVDisplayLink thread ──add(data:1)──► DispatchSourceUserDataAdd (main queue)
                                         Euler integration of v'=-a·v^b
                                         → callback(delta) → applyDelta(...)
```

---

## Module reference

### AppDelegate

Root coordinator. Owns the dependency graph — it creates and holds every object that needs to live for the app's lifetime. The order matters:

```
AppSettings → VolumeController → HUDController → GestureInterpreter → GestureEngine
```

On launch: if `AXIsProcessTrusted()` is false, shows onboarding instead of starting the engine. The engine is started inside the onboarding completion callback.

Menu bar item: `NSStatusBar.system.statusItem`. The menu is static (built once); it does not need to be rebuilt dynamically.

---

### GestureEngine

**Input layer.** Owns three event sources:

1. **`NSEvent.addGlobalMonitorForEvents(.rotate)`** — fires when another app is frontmost. This is the common case (the user is in Safari, Xcode, etc.).
2. **`NSEvent.addLocalMonitorForEvents(.rotate)`** — fires when our own app is frontmost (e.g. the Settings window is open and focused).
3. **CGEventTap** at `cgSessionEventTap` / `.headInsertEventTap` / `.listenOnly` — catches gesture events at the session level, covering the case where no app window has focus (desktop, Finder with no window). CGEventType 29 is the undocumented gesture event type; wrapping it in `NSEvent(cgEvent:)` lets us read `.rotation`.

All three call `handle(_:)` on the main actor via `Task { @MainActor in ... }`.

`handle` checks:
1. Is the frontmost app bundle ID in `settings.excludedBundleIDs`? → skip.
2. Is fallback mode on and the modifier not held? → skip.
3. Dispatch `.began`/`.ended`/`.cancelled` phases to delegate before sending the delta.

**Important:** `NSEvent.addGlobalMonitorForEvents` returns `nil` and silently does nothing if Accessibility permission is not granted. This is why the engine checks `AXIsProcessTrusted()` before calling `start()`.

---

### GestureInterpreter

**Core logic.** Converts raw degrees to scalar volume/brightness deltas.

#### Target locking

The `lockedTarget` is resolved once at `gestureEngineDidBeginGesture` while the modifier key is still held. All subsequent calls — per-event, end, fling — use `lockedTarget`. This prevents the bug where releasing Control mid-gesture (or at lift-off) causes the fling to affect volume instead of brightness.

#### Delta mapping

```
degreesForFullRange = degreesPerStep * 36  (default 5 * 36 = 180°)
scalar = degrees / degreesForFullRange
scalar = applyAcceleration(scalar, speed: |degrees|)
finalDelta = Float(scalar * sensitivity * 20)
```

The `sensitivity * 20` factor: sensitivity default is 0.05, so `0.05 * 20 = 1.0`, meaning the mapping is direct at default settings. This lets the UI slider range (0.01–0.20) map to a humanly-legible 1%–20% without making the user think about the `* 20` factor.

#### Acceleration

```swift
velocityFactor = clamp((|degrees| - 2.0) / 28.0, 0, 1)
powered = |scalar|^(1/accel)
blended = |scalar| + (powered - |scalar|) * velocityFactor
```

`accel > 1` makes the exponent `1/accel < 1`, which compresses large magnitudes (power curve bends toward zero), making fast rotations relatively smaller and slow ones relatively larger — the opposite of what you'd expect. This is intentional: it means slow deliberate turns are precise and fast flings travel further via the `velocityFactor` blend rather than a raw power boost.

---

### FlingEngine

**Post-lift momentum.** No timer fires during an active gesture — all live deltas come directly from trackpad events. The fling only runs after lift-off.

#### Velocity tracking

Two signals are maintained during the gesture:

- `emaVelocity` (EMA, α=0.55) — smooth signed velocity in deg/s. Used for direction (sign).
- `peakVelocity` (decaying max, factor 0.85 per event) — unsigned peak speed seen. Used for fling strength.

The peak catches short fast flicks (2–3 events) that EMA underestimates. Example: a 2-event 80 deg/s flick gives EMA ≈ 51 deg/s but peak ≈ 80 deg/s.

#### CVDisplayLink + DispatchSourceUserDataAdd

Why not just `DispatchSourceTimer` + `DispatchQueue.main.async`?

The original implementation used this pattern and caused jitter: 120Hz timer → 120 `main.async` blocks/sec → main queue backlog → multiple concurrent volume writes → out-of-order writes (volume jumping backward). `DispatchSourceUserDataAdd` solves this by coalescing: if the main thread hasn't drained yet when the next tick fires, the two signals add up and the handler runs once with `source.data == 2`, stepping the integrator twice in one call. The main thread never accumulates a backlog.

CVDisplayLink is used because it fires on a high-priority thread at the display's actual refresh rate (60 or 120 Hz), which is the correct rate for animation.

#### DragCurve physics

Euler integration of the drag differential equation:

```
v'(t) = -a · v^b     where a=30.0, b=0.72
Δv per tick = a · v^b · dt    (dt = 1/120)
stop when v < 0.5 deg/s
```

The exponent `b < 1` produces a "heavy drag" curve: deceleration is fast initially (high speed → high drag) then slows to a coast at low speed. This feels like a physical flywheel, not like easing.

---

### VolumeController

**CoreAudio wrapper.** Key design: `adjustVolume(by:)` writes CoreAudio *silently* — no media key, no HUD. `showHUD(increasing:)` posts one NX_SYSDEFINED media key event. These are intentionally separate.

Why? If a media key is posted on every event (100+ per second during rotation), macOS snaps the volume to the nearest 6.25% step on each keypress, undoing the smooth CoreAudio write. Posting once at gesture end shows the HUD at the correct final value without any snapping.

Volume is maintained in `currentVolume: Float` (local cache). It is initialized from CoreAudio on `init()` and updated on every write. It is **not** re-read from CoreAudio on each delta — this avoids a round-trip but means if another app changes volume mid-gesture the cache drifts. This is an acceptable trade-off for latency.

Reads/writes `kAudioDevicePropertyVolumeScalar` on the default output device, falling back to per-channel writes (L/R channels 1/2) if the master channel (0) fails.

---

### BrightnessController

**Built-in display:** `DisplayServicesGetBrightness` / `DisplayServicesSetBrightness` from `DisplayServices.framework` (private, loaded via `dlopen`). The native macOS OSD HUD is shown via `OSDManager.showImage:onDisplayID:…` from `OSD.framework` (also private).

**External displays:** Same `DisplayServices` call attempted first. If that fails, DDC (Display Data Channel) brightness control via `BrightnessControllerDDC`.

**Below-zero brightness (external only):** The logical brightness scale is `0.0–2.0`. Hardware brightness occupies `1.0–2.0` (mapped to `0.0–1.0` on the hardware). Below 1.0, hardware is set to 0 and `CGSetDisplayTransferByTable` applies a software gamma multiplier to dim the image further. This allows "dimmer than off" for dark environments.

**OSD on external displays:** The native `OSDManager` is broken for external displays on macOS Tahoe (26.x). A custom `NSWindow` overlay is shown instead: a compact dark bar with a progress fill and the display name, fading out after 1.2s.

**Display-under-cursor:** `displayUnderCursor()` uses `CGGetDisplaysWithPoint(NSEvent.mouseLocation)` to find which `CGDirectDisplayID` the cursor is on. This is called at the start of every brightness adjustment so the correct display is always targeted.

---

### BrightnessControllerDDC

DDC I2C brightness for external displays. Two paths:

**arm64 (Apple Silicon):** `IOAVServiceCreateWithService` + `IOAVServiceWriteI2C` / `IOAVServiceReadI2C` from IOKit.framework. The service objects are found by walking the IORegistry for `DCPAVServiceProxy` nodes with `Location == "External"`, then matched to `CGDirectDisplayID` by EDID UUID, product name, serial number, and IO registry path (scored match with fallback to ordinal position).

**Intel fallback:** `IOFBGetI2CInterfaceCount` + `IOFBCopyI2CInterfaceForBus` + `IOI2CSendRequest`. Matches framebuffer to display via vendor/product ID from `IODisplayCreateInfoDictionary`.

DDC writes are asynchronous (dispatched to a background queue for the arm64 path) to avoid blocking the main thread on slow USB-C hubs.

---

### HapticEngine

`NSHapticFeedbackManager.defaultPerformer` — works only on Force Touch trackpads. On non-Force-Touch hardware (Magic Mouse, external keyboards) `defaultPerformer` returns nil and the engine silently does nothing.

State is tracked separately for volume and brightness so independent gestures (e.g. Control held mid-session) don't cross-contaminate notch positions.

**Notch detection:** `floor(value / 0.10) != floor(lastValue / 0.10)` — fires whenever the value crosses a 10% boundary in either direction. Rate limiting is bypassed for notch bumps so they always fire even during fast sweeps.

**Rate limiting:** `minTickInterval = 0.035s` → max ~28 ticks/s. Without this, 120Hz events would drive the Force Touch actuator into a continuous buzz.

---

### HUDController / HUDView

`HUDController` manages a single floating `NSWindow` (level: `.floating`, ignores mouse, joins all spaces, stationary). The window is created lazily on first `show(volume:)` call. Position is near the cursor at gesture start, clamped to the screen's visible frame.

Auto-hide: a `Task` sleeps 1.2s then animates `isVisible = false` over 0.3s. A new `show()` call cancels the pending hide task.

`HUDView` is SwiftUI with `@Observable HUDState`. The arc uses `Circle().trim(from: 0, to: volume)` with an `AngularGradient`. The speaker icon switches symbol using `.contentTransition(.symbolEffect(.replace))`. The percentage uses `.contentTransition(.numericText())` for the counting animation.

---

### PermissionsManager + OnboardingView

`AXIsProcessTrusted()` — returns `true` only if the *currently running binary* has an entry in the TCC database with `auth_value = 2` (allowed) and the code signature matches the stored hash.

**The stale-TCC problem:** After replacing the binary (new build), the binary hash changes but the TCC entry still shows "allowed". `AXIsProcessTrusted()` returns `false` because the hash mismatch. The fix is `tccutil reset Accessibility com.trackpadvolumeknob` which removes the entry entirely, then the user re-enables in System Settings.

`resetAndRequestPermission()` runs `tccutil reset` via `Process()` then opens System Settings after a 0.3s delay (to let tccutil finish). `OnboardingView` polls `AXIsProcessTrusted()` every 1 second using a `Task` while loop until it returns `true`, then shows the "Get Started" button.

**Why not `kAXTrustedCheckOptionPrompt`?** It triggers a system dialog asking to add the app, but it doesn't help if an entry already exists with a wrong hash. The explicit `tccutil reset` + re-grant flow is more reliable.

---

### AppSettings

Single `@MainActor` `@Observable` class with `UserDefaults.standard` persistence. Every `@Published` property has a `didSet` that writes to UserDefaults immediately — no batching, no dirty tracking. Settings changes take effect on the next gesture event (read live from settings at each `applyDelta` call).

**`excludedBundleIDs`** is stored as a JSON-encoded `[String]` data blob in UserDefaults. First launch gets `defaultExcludedBundleIDs` (22 preset apps). Subsequent launches load the saved version.

**`hapticLevel`** default is `.medium`.

---

## Permissions and entitlements

`TrackpadVolumeKnob.entitlements`:

```xml
com.apple.security.app-sandbox = false
com.apple.security.temporary-exception.accessibility = true
```

Sandbox is disabled because:
- `CGEventTap` requires it (not allowed in sandboxed apps without special review).
- DDC brightness via IOKit requires direct hardware access.
- `tccutil` is an external process that cannot be spawned from a sandboxed app.

The accessibility entitlement key enables `NSEvent.addGlobalMonitorForEvents` without requiring an additional `Input Monitoring` permission prompt.

---

## Known issues and future work

**1. HUD shows volume even when changing brightness**

`showHUD(increasing:)` on `VolumeController` fires at gesture end regardless. For brightness gestures the OSD is shown per-adjustment (in `BrightnessController`). The volume HUD at gesture end is harmless but slightly confusing. Fix: gate `showHUD` on `lockedTarget == .volume` in `GestureInterpreter.gestureEngineDidEndGesture`.

**2. No release build pipeline**

`scripts/deploy.sh` uses `swift build` (debug). For distribution add `swift build -c release` and a DMG creation step. A release build is ~3× smaller and faster.

**3. Swift 6 strict concurrency**

The core target uses `.swiftLanguageMode(.v5)`. To migrate: mark `FlingEngine`'s background-read properties `nonisolated(unsafe)`, change callback signatures to `@Sendable`, and re-enable `.v6` mode.

**4. External display DDC matching**

The EDID-based matching in `BrightnessControllerDDC` works for most setups but can fail on daisy-chained hubs or displays with duplicate EDID values. If brightness doesn't work on an external display, check Console.app debug logs with debug logging enabled.

**5. MultitouchSupport.framework**

Listed in RESEARCH.md as a future option. Would allow gesture detection without Accessibility permission and at lower latency. The framework is private and the ABI changes across macOS versions, so it is not currently implemented.

---

## Debugging

Enable debug logging in Settings → General → Enable debug logging. Then open Console.app, filter by process "TrackpadVolumeKnob".

Key log messages:

| Message | Meaning |
|---|---|
| `GestureEngine: started (global + local monitors + CGEventTap)` | Engine running, all event sources active |
| `GestureEngine: CGEventTap installed` | CGEventTap successfully created |
| `GestureEngine: skipping — com.apple.Maps is excluded` | App exclusion working |
| `GestureEngine: rotation X.XXX° phase=Y` | Raw rotation events arriving |
| `Interpreter: target=volume Δ°=X Δ=Y` | Delta being applied to volume |
| `VolumeController: set to X.XXX` | CoreAudio write confirmed |
| `BrightnessController: built-in → X.XXX` | Built-in brightness write |
| `BrightnessController: external NNNNN logical=X hw=Y gamma=Z` | External brightness write |

If you see no `GestureEngine: started` message, `AXIsProcessTrusted()` returned false. Run `swift scripts/check_ax.swift` from the workspace root to verify.
