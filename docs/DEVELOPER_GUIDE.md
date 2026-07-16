# Mac Trackpad Fix — Developer Guide

Full architecture, module reference, design decisions, and release pipeline. Read top to bottom if you're new to the codebase.

---

## Repository layout

```
mac-trackpad-fix/
├── Package.swift                         Swift package manifest
├── MacTrackpadFix/
│   ├── App/                              Thin executable target (MacTrackpadFixApp)
│   │   ├── main.swift                    NSApplicationMain entry point
│   │   └── AppDelegate.swift             Root coordinator + wiring + TCC reset
│   ├── Sources/                          Library target (MacTrackpadFixCore)
│   │   ├── AppSettings.swift             All user preferences + exclusion list
│   │   ├── GestureEngine/
│   │   │   └── GestureEngine.swift       Input: NSEvent monitors + CGEventTap
│   │   ├── GestureInterpreter/
│   │   │   ├── GestureInterpreter.swift  Raw degrees/magnification → delta
│   │   │   ├── FlingEngine.swift         Post-lift momentum (CVDisplayLink)
│   │   │   └── HapticEngine.swift        Force Touch feedback
│   │   ├── VolumeController/
│   │   │   └── VolumeController.swift    CoreAudio read/write + HUD trigger
│   │   ├── BrightnessController/
│   │   │   ├── BrightnessController.swift   DisplayServices + OSD + gamma
│   │   │   └── BrightnessControllerDDC.swift  DDC over IOAVService / I2C
│   │   ├── HUD/
│   │   │   ├── HUDController.swift       Floating NSWindow lifecycle
│   │   │   └── HUDView.swift             SwiftUI arc + icon + percentage
│   │   ├── Permissions/
│   │   │   ├── PermissionsManager.swift  AXIsProcessTrusted + tccutil reset
│   │   │   └── OnboardingView.swift      First-run permission UI
│   │   ├── Settings/
│   │   │   └── SettingsView.swift        5-tab preferences window
│   │   └── Utilities/
│   │       ├── LaunchAtLoginManager.swift  SMAppService wrapper
│   │       └── Logger.swift              os.Logger wrapper
│   └── Resources/
│       ├── Info.plist
│       └── MacTrackpadFix.entitlements
├── MacTrackpadFixTests/                  XCTest target
├── GestureTest/
│   └── main.swift                        Standalone NSEvent monitor debug tool
├── scripts/
│   ├── deploy.sh                         Build + sign + install locally
│   ├── build_pkg.sh                      Build distributable .pkg
│   ├── assemble_app.sh                   Assemble MacTrackpadFix.app from build
│   ├── postinstall                       pkg postinstall: TCC reset + rename
│   ├── release.py                        Full release pipeline (Drive + GitHub)
│   ├── constants.py                      Release infrastructure constants
│   ├── sign_release.sh                   Sparkle ed25519 signing helper
│   └── check_ax.swift                    AXIsProcessTrusted probe
├── appcast.xml                           Sparkle feed (GitHub raw, for old users)
├── make_icon.swift                       Icon generator script
└── docs/
    ├── USER_GUIDE.md
    └── DEVELOPER_GUIDE.md  <- you are here
```

---

## Build system

**Swift Package Manager, swift-tools-version 6.0, macOS 14 minimum.**

| Target | Type | Swift mode | Notes |
|---|---|---|---|
| `MacTrackpadFixApp` | Executable | Swift 6 | Entry point only |
| `MacTrackpadFixCore` | Library | Swift 5 | All logic — see note below |
| `GestureTest` | Executable | Swift 6 | Dev debug tool, not shipped |

### Why Swift 5 mode for core?

`FlingEngine` uses `DispatchSourceTimer` + `DispatchQueue.main.async` for its CVDisplayLink-based momentum loop. Swift 6 strict actor isolation rejects this pattern with `SendingRisksDataRace` errors even though the threading is provably safe (timer callbacks write only to local captured variables, all controller calls hop to main via `DispatchQueue.main.async`). Using `.swiftLanguageMode(.v5)` silences the false positives while keeping the Swift 6 toolchain for everything else.

To migrate to full Swift 6: mark timer-captured variables `nonisolated(unsafe)` and change callback signatures to `@Sendable`.

---

## Local development

```bash
# Build + sign + install + launch
./scripts/deploy.sh

# Build only (debug)
swift build

# Release build
swift build -c release

# Tests
swift test

# Gesture event probe (no full app)
swift build --product GestureTest
.build/debug/GestureTest
```

`deploy.sh` also resets TCC (`tccutil reset Accessibility com.trackpadvolumeknob`) and clears `LastLaunchedBinaryHash` from UserDefaults before launching, so every local deploy triggers the onboarding permission flow exactly as a real update would.

---

## Release pipeline

Releases are managed by `scripts/release.py`. It handles everything end-to-end:

```bash
python3 scripts/release.py 2.1.0 "What changed in this release"
```

**Steps performed:**
1. Bumps `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`
2. `swift build -c release`
3. `scripts/assemble_app.sh` — assembles `MacTrackpadFix.app` from build output
4. `scripts/build_pkg.sh` — builds `MacTrackpadFix-VERSION.pkg` with `postinstall` script
5. `sign_update` (Sparkle ed25519) — signs the pkg, extracts signature + length
6. Updates `appcast.xml` (GitHub, pkg URL = GitHub release) and generates `appcast_drive.xml` (Drive, pkg URL = Drive stable ID)
7. Uploads pkg to Google Drive (stable file ID — URL never changes)
8. Uploads `appcast_drive.xml` to Google Drive (overwrites same file ID)
9. Creates GitHub release + uploads pkg as asset
10. `git commit && git push`

**Dual appcast strategy:**

Old users (pre-2.x) have `SUFeedURL` pointing to GitHub raw. New users (2.x+) point to Google Drive. Both serve the same Sparkle XML format, but the `<enclosure url>` differs:
- GitHub appcast → pkg download from GitHub releases
- Drive appcast → pkg download from Google Drive stable URL

This ensures old users can update without having Google Drive access, while new users benefit from Drive's reliability.

**Google Drive file IDs** (stable, never change — see `scripts/constants.py`):
- Appcast: `1Tm6XmjizYSJ-NWECo1X8Quj2XjhArT3y`
- PKG: `1K8Qir_1TdmJpFpn-BJfgRfX0qd4Z-5kd`

**Sparkle signing key** is stored in the macOS keychain. The public key (`SUPublicEDKey`) is baked into `Info.plist`. Running `sign_update` requires keychain access — it cannot be automated non-interactively without exporting the private key.

---

## Data flow

```
Two-finger gesture on trackpad
         |
         | NSEvent .rotate / .magnify  (phase: began/changed/ended)
         | CGEventType 29 via CGEventTap (fallback for desktop focus)
         v
+--------------------+
|   GestureEngine    |  handle(event:) / handlePinch(event:)
|                    |  - App exclusion check
|                    |  - Fallback modifier check
|                    |  - Routes .rotate -> gestureEngine(_:didReceive:)
|                    |  - Routes .magnify -> gestureEngine(_:didReceivePinch:)
+--------+-----------+
         |
         | RotationEvent(degrees, timestamp, phase)
         | PinchEvent(magnification, timestamp, phase)
         v
+------------------------+
| GestureInterpreter     |
|                        |
| ROTATION path:         |
|   gestureEngineDidBeginGesture -> lock target, reset state
|   didReceive(rotation) -> dead zone -> fling.track -> applyDelta
|   gestureEngineDidEndGesture -> showHUD -> fling.startFling
|                        |
| PINCH path:            |
|   gestureEngineDidBeginPinch -> reset classifier state
|   didReceivePinch      -> classifier window (4 events)
|                          -> if committed to pinch: applyDelta
|   gestureEngineDidEndPinch -> reset
|                        |
| CLASSIFIER:            |
|   Accumulate |rotation_mag| and |pinch_mag * 60| over first 4 events
|   Commit to whichever is larger. Rotation always immediate (no wait).
+----+-----------+-------+
     |           |
     v           v
VolumeController  BrightnessController
CoreAudio write   DisplayServices / DDC / gamma
     |
     v
HapticEngine (notch detection, rate limiting)

FlingEngine (post-lift only):
  CVDisplayLink -> DispatchSourceUserDataAdd -> Euler v'=-a*v^b
```

---

## Module reference

### AppDelegate

Root coordinator. Creates and holds every long-lived object:

```
AppSettings -> VolumeController -> HUDController -> GestureInterpreter -> GestureEngine
```

**Post-update TCC reset** (`handlePostUpdateTCCReset`): on every launch, SHA-256 hashes `Bundle.main.executableURL` and compares to `LastLaunchedBinaryHash` in UserDefaults. If different, runs `tccutil reset Accessibility com.trackpadvolumeknob` and stores the new hash. This fires on any binary change regardless of how the update was delivered (Sparkle, manual drag, local deploy).

CommonCrypto is imported for the SHA-256 hash.

---

### GestureEngine

Three event sources, all calling `handle(_:)` on `@MainActor`:

1. **`NSEvent.addGlobalMonitorForEvents([.rotate, .magnify])`** — fires when another app is frontmost (the common case).
2. **`NSEvent.addLocalMonitorForEvents([.rotate, .magnify])`** — fires when our own app is active (Settings window open).
3. **CGEventTap** at `cgSessionEventTap` / `.listenOnly` — catches gestures at session level, covering the desktop/Finder case. CGEventType 29 is the undocumented gesture event type; `NSEvent(cgEvent:)` exposes `.rotation` and `.magnification`.

`handle(_:)` flow:
1. Exclusion list check → skip if frontmost app is excluded
2. Fallback mode check → skip if modifier not held
3. Route by event type: `.rotate` → rotation delegate, `.magnify` → pinch delegate

---

### GestureInterpreter

#### Gesture classifier

Rotation and pinch events can fire simultaneously — macOS leaks small magnify events during rotation and vice versa. The classifier disambiguates:

- **Rotation events** are always processed immediately with no delay. `gestureEngineDidBeginGesture` sets `activeGesture = .rotate` which blocks all pinch events.
- **Pinch events** go through a 4-event classification window. During the window, both `|rotation_degrees|` and `|magnification * 60|` are accumulated. At event 4, the gesture commits to whichever type has higher total magnitude. If rotation already has `activeGesture = .rotate`, pinch events are dropped entirely.

The normalization factor `60.0` comes from empirical data: a typical rotation event is ~3°/event while a typical pinch is ~0.05 magnification/event; `0.05 * 60 = 3.0` puts them on the same scale.

#### Target locking

`lockedTarget` is resolved once at `gestureEngineDidBeginGesture` while the modifier key is still held. All subsequent calls (per-event, end, fling) use `lockedTarget`. This prevents modifier key release mid-gesture from changing what the fling controls.

#### Delta mapping

```
degreesForFullRange = degreesPerStep * 36   (default 5 * 36 = 180°)
scalar = degrees / degreesForFullRange
scalar = applyAcceleration(scalar, speed: |degrees|)
finalDelta = Float(scalar * sensitivity * 20)
```

The `sensitivity * 20` factor: default sensitivity is 0.05, so `0.05 * 20 = 1.0` — direct mapping at defaults. The slider range (0.01–0.20) expresses human-legible percentages without the user needing to understand the internal scaling.

#### Acceleration

```
velocityFactor = clamp((|degrees| - 2.0) / 28.0, 0, 1)
powered = |scalar|^(1 / accel)
blended = |scalar| + (powered - |scalar|) * velocityFactor
```

`accel > 1` makes the exponent `1/accel < 1`, compressing large magnitudes (the power curve bends toward zero at high speed). The `velocityFactor` blend means slow turns are linear and precise; fast flings get the compressed (larger) component blended in.

---

### FlingEngine

Post-lift momentum only. No timer fires during an active gesture — all live deltas come directly from trackpad events.

#### Velocity tracking

Two signals maintained per-event:
- `emaVelocity` (EMA, α=0.55): smooth signed velocity. Used for direction.
- `peakVelocity` (decaying max, factor 0.85/event): unsigned peak speed. Used for fling strength.

Peak catches short fast flicks (2–3 events) that EMA underestimates.

#### CVDisplayLink + DispatchSourceUserDataAdd

A naive `DispatchSourceTimer` + `DispatchQueue.main.async` pattern causes jitter at 120Hz: timer fires 120×/sec → main queue backlog → concurrent volume writes → out-of-order writes (volume jumps backward). `DispatchSourceUserDataAdd` coalesces: if the main thread hasn't drained when the next tick fires, `source.data == 2`, so the handler runs once and steps the integrator twice. No backlog accumulates.

#### DragCurve physics

Euler integration: `v'(t) = -a * v^b` where `a=30.0, b=0.72`, `dt = 1/120s`. Stop when `v < 0.5 deg/s`.

Exponent `b < 1` = "heavy drag": deceleration is fast initially (high speed = high drag) then coasts at low speed. Feels like a physical flywheel.

---

### VolumeController

**CoreAudio wrapper.** `adjustVolume(by:)` writes CoreAudio silently — no media key. `showHUD(increasing:)` posts one `NX_SYSDEFINED` media key event. Intentionally separate.

Why? If a media key is posted on every event (100+/sec during rotation), macOS snaps volume to the nearest 6.25% step on each keypress, undoing the smooth CoreAudio write. One key at gesture end shows the HUD at the correct final value with no snapping.

`currentVolume` is a local cache, initialized from CoreAudio on `init()` and updated on every write. Not re-read on each delta — avoids round-trip latency at the cost of drift if another app changes volume mid-gesture (acceptable trade-off).

Reads/writes `kAudioDevicePropertyVolumeScalar` on the default output device. Falls back to per-channel (L/R channels 1/2) if master channel (0) fails.

---

### BrightnessController

**Built-in display:** `DisplayServicesGetBrightness` / `DisplayServicesSetBrightness` from `DisplayServices.framework` (private, loaded via `dlopen`). Native OSD via `OSDManager` from `OSD.framework` (also private).

**External displays:** `DisplayServices` attempted first, falls back to DDC.

**Below-zero brightness (external only):** Logical scale is `0.0–2.0`. Hardware occupies `1.0–2.0` (mapped to `0.0–1.0` on hardware). Below 1.0: hardware set to 0, `CGSetDisplayTransferByTable` applies software gamma to dim further. Allows dimmer than hardware minimum.

**OSD on external displays (macOS Tahoe+):** Native `OSDManager` is broken for external displays on 26.x. A custom `NSWindow` overlay is shown instead: compact dark bar with progress fill + display name, fades after 1.2s.

**Display-under-cursor:** `CGGetDisplaysWithPoint(NSEvent.mouseLocation)` at the start of each adjustment. Always targets the display the cursor is on.

---

### BrightnessControllerDDC

DDC I2C brightness for external displays.

**arm64 (Apple Silicon):** `IOAVServiceCreateWithService` + `IOAVServiceWriteI2C` / `IOAVServiceReadI2C`. Finds services by walking IORegistry for `DCPAVServiceProxy` nodes with `Location == "External"`, matched to `CGDirectDisplayID` by EDID UUID, product name, serial number, and IO registry path (scored match with ordinal fallback). Writes dispatched to background queue to avoid blocking main thread on slow USB-C hubs.

**Intel fallback:** `IOFBGetI2CInterfaceCount` + `IOFBCopyI2CInterfaceForBus` + `IOI2CSendRequest`. Matched via vendor/product ID from `IODisplayCreateInfoDictionary`.

---

### HapticEngine

`NSHapticFeedbackManager.defaultPerformer` — works only on Force Touch trackpads. Returns nil silently on non-Force-Touch hardware.

State tracked separately for volume and brightness to prevent cross-contamination.

**Notch detection:** `floor(value / 0.10) != floor(lastValue / 0.10)` — fires when crossing any 10% boundary in either direction. Rate limiting bypassed for notch bumps.

**Rate limiting:** `minTickInterval = 0.035s` (~28 ticks/s max). Without this, 120Hz events drive the actuator into a continuous buzz.

---

### HUDController / HUDView

Single floating `NSWindow` (level `.floating`, ignores mouse, joins all spaces, stationary). Created lazily on first `show()`. Positioned near cursor at gesture start, clamped to screen's visible frame.

Auto-hide: `Task` sleeps 1.2s → animates `isVisible = false` over 0.3s. New `show()` cancels pending hide.

`HUDView` uses `@Observable HUDState`. Arc: `Circle().trim(from: 0, to: volume)` with `AngularGradient`. Icon: `.contentTransition(.symbolEffect(.replace))`. Percentage: `.contentTransition(.numericText())`.

---

### PermissionsManager

`AXIsProcessTrusted()` returns true only if the running binary has a TCC entry with `auth_value = 2` and the code signature matches the stored hash.

**The stale-TCC problem:** After replacing the binary, the hash changes but the TCC entry still shows "allowed". `AXIsProcessTrusted()` returns false. Fix: `tccutil reset Accessibility com.trackpadvolumeknob` removes the entry; user re-enables in System Settings.

`resetAccessibilityTrust()` runs `tccutil reset` via `Process()`. `openAccessibilitySettings()` opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.

**OnboardingView:** On appear, calls `AXIsProcessTrustedWithOptions(prompt: false)` which silently registers the app in the TCC list without showing a system dialog. Then polls `AXIsProcessTrusted()` every 1s until true. User clicks "Open System Settings", flips the toggle, "Check Again" confirms, "Get Started" closes onboarding and starts the engine.

---

### AppSettings

`@MainActor @Observable` class. Every property has a `didSet` writing to `UserDefaults` immediately.

`excludedBundleIDs` stored as JSON-encoded `[String]` blob. First launch gets `defaultExcludedBundleIDs` (22 presets).

---

## Permissions and entitlements

`MacTrackpadFix.entitlements`:
```xml
com.apple.security.app-sandbox = false
com.apple.security.temporary-exception.accessibility = true
```

Sandbox disabled because:
- `CGEventTap` is not permitted in sandboxed apps without special review
- DDC brightness requires direct IOKit hardware access
- `tccutil` is an external process that cannot be spawned from sandbox

The accessibility entitlement enables `NSEvent.addGlobalMonitorForEvents` without an additional Input Monitoring permission prompt.

---

## Bundle identifier

The bundle identifier `com.trackpadvolumeknob` is intentionally kept from the original name. Changing it would:
- Break Sparkle updates (Sparkle matches by bundle ID)
- Reset all UserDefaults preferences for existing users
- Require existing users to re-grant Accessibility permission permanently (no migration path)

The display name (`CFBundleDisplayName`, `CFBundleName`) and binary name (`CFBundleExecutable`) are all "Mac Trackpad Fix" — only the internal reverse-DNS identifier retains the old name.

---

## Known issues

**1. HUD shows volume during brightness gestures**

`showHUD(increasing:)` on `VolumeController` fires at gesture end regardless of `lockedTarget`. For brightness the OSD appears per-adjustment via `BrightnessController`. The volume HUD at end is harmless but slightly confusing. Fix: gate `showHUD` on `lockedTarget == .volume` in `gestureEngineDidEndGesture`.

**2. No Apple Developer ID signing**

The app is ad-hoc signed (`codesign --sign -`). This means:
- TCC permission resets on every binary change (handled by the checksum detector)
- Gatekeeper will warn users on first launch (can be bypassed with right-click → Open)
- Future: enroll in Apple Developer Program and sign with Developer ID Application certificate

**3. External display DDC matching**

EDID-based matching in `BrightnessControllerDDC` can fail on daisy-chained hubs or displays with duplicate EDID values. Check Console.app debug logs for `BrightnessControllerDDC` messages.

**4. Swift 6 strict concurrency**

Core target uses `.swiftLanguageMode(.v5)`. To migrate: mark `FlingEngine` background-read properties `nonisolated(unsafe)`, change callback signatures to `@Sendable`, re-enable `.v6`.

---

## Debugging

Enable in Settings → General → Enable debug logging. Filter Console.app by process "MacTrackpadFix".

| Message | Meaning |
|---|---|
| `GestureEngine: started (global + local monitors + CGEventTap)` | All event sources active |
| `GestureEngine: rotation X.XXX° phase=Y` | Raw rotation event |
| `GestureEngine: pinch X.XXXX phase=Y` | Raw pinch event |
| `Classifier: committed to ROTATE/PINCH (rot=X pinch=Y)` | Gesture type resolved |
| `Interpreter: target=volume Δ°=X Δ=Y` | Rotation delta applied |
| `Interpreter: pinch target=brightness Δ=Y` | Pinch delta applied |
| `BrightnessController: built-in -> X.XXX` | Built-in brightness write |
| `BrightnessController: external NNNNN logical=X hw=Y gamma=Z` | External brightness write |

If no `GestureEngine: started` appears, `AXIsProcessTrusted()` returned false. Run `swift scripts/check_ax.swift` to verify.
