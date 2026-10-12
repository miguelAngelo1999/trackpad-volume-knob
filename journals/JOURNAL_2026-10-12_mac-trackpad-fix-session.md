# Journal — 2026-10-12 — Mac Trackpad Fix: Flywheel, Stability, Onboarding

## Summary

Long session covering: flywheel/inertia momentum implementation (and its crashes),
volume jitter root cause and fix, haptic feedback, pinch gesture for brightness,
silent crash debugging, gesture disambiguation, launch-at-login fix, onboarding
improvements, and a stale SPM build cache issue that masked all UI changes for weeks.

---

## 1. Flywheel / Inertia Momentum — Ported from mac-mouse-fix

### Goal
Make volume/brightness changes smoother by adding post-lift fling momentum,
similar to mac-mouse-fix's `DragInertiaEngine`.

### Reference implementation read
- `mac-mouse-fix/Helper/Core/Drag/DragInertiaEngine.m` — flywheel + DragCurve physics
- `DragCurve.swift` — `v'(t) = -a·v^b` differential equation, solved analytically
- `ModifiedDragOutputVolumeBrightness.m` — how mac-mouse-fix uses it for volume/brightness

### First attempt: DispatchSourceTimer + DispatchQueue.main.async
Crashed immediately with `EXC_BREAKPOINT` / `SIGTRAP` at:
```
_dispatch_assert_queue_fail → _swift_task_checkIsolatedSwift
→ closure #1 in FlingEngine.startFlywheelTimer()
```

**Root cause:** Swift 6 strict actor isolation injects `dispatch_assert_queue` checks
at every call to a `@MainActor`-isolated method. The DispatchSourceTimer fires on a
background thread. The `Task { @MainActor in ... }` wrapper is not sufficient — the
check fires on the OUTER closure (the timer event handler) before the Task enqueues.

**Fix:** Downgraded `TrackpadVolumeKnobCore` to `.swiftLanguageMode(.v5)` in
Package.swift. Swift 5 mode compiles with the Swift 6 toolchain but without the
strict runtime actor isolation checks. The threading model is safe by construction
(everything dispatched to main before touching controllers) but Swift 6 can't
prove it statically due to the GCD-based timer pattern.

### Volume jitter (120Hz timer → racing writes)

After the crash fix, volume was jittery: logs showed multiple thread IDs (b46a7d,
b46a7e, b46a81) writing to CoreAudio simultaneously, volume jumping backward.

**Root cause:** 120Hz flywheel timer was queuing `DispatchQueue.main.async` blocks
faster than the main queue drained. Each block read `currentVolume`, added delta, wrote.
Concurrent reads of a stale `currentVolume` produced out-of-order writes.

**Fix:** Removed flywheel timer ENTIRELY during active gesture. Deltas are now
applied synchronously on the main thread directly from each trackpad event —
single-threaded, zero latency, zero races. Post-lift fling uses CVDisplayLink +
`DispatchSourceUserDataAdd` (coalescing) instead.

### DispatchSourceUserDataAdd coalescing
When the main thread is busy, CVDisplayLink fires multiple times before the handler
runs. `DispatchSourceUserDataAdd.add(data:1)` accumulates these — the handler runs
once with `source.data == N`, steps the integrator N times. Never a backlog of pending
volume writes.

---

## 2. Volume Stepping — postMediaKey per event

Volume was changing in discrete 6.25% steps regardless of rotation amount.

**Root cause:** `postMediaKey` (NX_KEYTYPE_SOUND_UP/DOWN) was called on EVERY gesture
event. Each call is equivalent to pressing F11/F12 — macOS snaps volume to the nearest
6.25% step, overriding the smooth CoreAudio write.

**Fix:** Split `VolumeController.adjustVolume(by:)` into:
- `adjustVolume(by:)` — silent CoreAudio write only, no media key, no HUD
- `showHUD(increasing:)` — one media key post, called ONCE at gesture end

Gesture mapping changed from `degreesPerStep` step model to direct scalar:
```
degreesForFullRange = degreesPerStep × 36  (default 5 × 36 = 180°)
scalar = degrees / degreesForFullRange
finalDelta = Float(scalar × sensitivity × 20)
```
180° of rotation sweeps the full 0→100% range at default settings.

---

## 3. Git Repository

Created public repo: `github.com/miguelAngelo1999/trackpad-volume-knob`
- Initially push failed: expired GitHub token in keychain → `gh auth login` fixed it
- Later moved to `github.com/miguelAngelo1999/trackpad-volume-knob` (same repo)

---

## 4. App Exclusion List — Prefix Matching Bug

**Bug:** Rotation while in Chrome Beta/Dev/Canary still changed volume.

**Root cause:** Exclusion list had `com.google.Chrome` (stable only). Exact string
matching meant `com.google.Chrome.beta`, `.dev`, `.canary` all slipped through.

**Fix:** Changed `isExcluded()` to prefix match:
```swift
bundleID == excluded || bundleID.hasPrefix(excluded + ".")
```
`com.google.Chrome` now covers all Chrome variants automatically. Also added
Chromium, Arc browser, Firefox Nightly to the default preset.

---

## 5. Haptic Feedback

`NSHapticFeedbackManager.defaultPerformer` with three patterns:

| Level | Volume | Brightness |
|---|---|---|
| Light | `.generic` tick | `.generic` tick |
| Medium | `.alignment` snap + `.levelChange` at 10% notches | `.generic` + `.alignment` notch |
| Strong | `.levelChange` click + notch bumps | `.alignment` + notch |

- Notch detection: `floor(value/0.10) != floor(lastValue/0.10)`
- Rate limited to ~28 ticks/s max to prevent actuator buzz
- Separate state per target (volume and brightness track independently)

---

## 6. Pinch → Brightness

Added `NSEvent.magnify` support:
- New `PinchEvent` struct + `GestureEngineDelegate` methods
- `handlePinch()` in GestureEngine
- Routed through `GestureInterpreter.gestureEngine(_:didReceivePinch:)`
- Scales magnification directly to brightness delta

**Bug:** Pinch in Chrome Beta was still changing brightness because Chrome Beta
(`com.google.Chrome.beta`) wasn't in the exclusion list. Fixed by prefix matching
(see §4).

**Design limitation:** Pinch-to-zoom is universal — unlike rotation, no app-detection
approach works because browsers zoom silently at the GPU compositor level with no log
output. Confirmed by watching `log stream` during pinch-to-zoom in Safari: zero
zoom-related messages. The exclusion list (prefix matching) is the correct solution.

---

## 7. Target Locking — Modifier Key Released Before Gesture Ends

**Bug:** Holding Control for brightness, rotating, then releasing fingers: brightness
AND volume both changed because Control was already released by the time
`gestureEngineDidEndGesture` fired.

**Root cause:** `resolvedTarget()` reads `NSEvent.modifierFlags` live. At gesture end,
modifiers are already released.

**Fix:** `lockedTarget` — resolved once in `gestureEngineDidBeginGesture` while the
modifier is still held. All subsequent calls (per-event, end, fling) use `lockedTarget`.

---

## 8. Silent Crash / Unresponsive Gestures

### Root cause 1: Task { @MainActor in } in CGEventTap callback
Every gesture event created a Swift concurrency Task. During rapid rotation,
50+ tasks/second pile up on the main actor executor. macOS monitors CGEventTap
responsiveness and silently disables taps that don't stay responsive.

**Fix:** Replaced all `Task { @MainActor in ... }` in GestureEngine with
`DispatchQueue.main.async` — direct queue hop, no Swift concurrency overhead.

### Root cause 2: CGEventTap silently disabled, no recovery
Once macOS disables the tap, gestures stop forever until app restart.

**Fix:** 5-second watchdog timer polls `CGEvent.tapIsEnabled`. If disabled, calls
`CGEvent.tapEnable(tap:enable:true)`. Reduced to **0.5s** after user reported
5-second unresponsive gaps. Also added `screensDidWakeNotification` observer to
re-enable immediately on display wake.

### Root cause 3: NSWorkspace.frontmostApplication at 50+ Hz
`NSWorkspace.shared.frontmostApplication` is an XPC round-trip. Called on every
gesture event during rapid rotation = 50+ XPC calls/second. Objects accumulate
faster than ARC drains them. Memory grew from 70MB to 198MB over time.

**Fix:** `frontmostBundleID()` caches result with 150ms TTL → max ~7 calls/second.

### Root cause 4: CVDisplayLink fires after display invalidation
If display sleeps while a fling is coasting, the CVDisplayLink fires against an
invalid display. Added `NSWorkspace.screensDidSleepNotification` handler that calls
`flingEngine.reset()`.

### Root cause 5: SHA256 of binary on every launch
`handlePostUpdateTCCReset()` was reading the entire binary and computing SHA256
to detect updates. For a 2MB binary this allocates a 2MB Data object on every launch.

**Fix:** Use file modification timestamp (`mtime`) instead — single stat() call, zero
allocation.

### Root cause 6: CVDisplayLink generation counter
`stopFling()` calls `CVDisplayLinkStop()` but the callback thread can fire once more
before stopping. Added `generation` counter to `FlingEngine` — stale callbacks check
`self.generation == myGeneration` and return early if they don't match.

---

## 9. Gesture Disambiguation — Rotation vs Pinch

**Problem:** macOS fires both `.rotate` and `.magnify` events simultaneously at gesture
start. User rotating for volume would sometimes also trigger brightness change.

**Fix:** Three-layer heuristic in `GestureEngine.handle()` / `handlePinch()`:

1. **Gesture mutex:** Once one type is committed, suppress all events of the other
   type until that gesture ends. Prevents a clean rotation from leaking magnify events.

2. **80ms decision window:** At gesture start, accumulate both `|degrees|` and
   `|magnification|`, normalized by typical full-gesture scale (`rotNorm=8°`,
   `magNorm=0.06`). After 80ms (or when one score leads by >0.3), commit the lock to
   the dominant type. Conservative: pinch events suppressed during the window.

3. **Minimum threshold:** Pinch only fires once accumulated `|mag| >= 0.015`.
   Filters out sub-threshold magnify events that fire briefly at rotation start.

---

## 10. Launch at Login

### SMAppService broken
`SMAppService.mainApp.register()` tied login item to code signing identity. Ad-hoc
re-signing on every `deploy.sh` run changes the identity hash → macOS silently drops
the registration. Status returned `.notFound` in production.

**Fix:** Replaced with **LaunchAgent plist** in `~/Library/LaunchAgents/com.trackpadvolumeknob.plist`:
```xml
<key>ProgramArguments</key>
<array><string>/Applications/MacTrackpadFix.app/Contents/MacOS/MacTrackpadFix</string></array>
<key>RunAtLoad</key><true/>
```
References app by PATH, not signing identity. Survives every binary update.
`launchctl load/unload` is called immediately so no reboot needed.

---

## 11. Onboarding Improvements

### Launch-at-login toggle in onboarding
Added to first-run screen so users configure it during setup.

### Auto-refocus after System Settings
When user grants accessibility in System Settings, the polling loop detects
`AXIsProcessTrusted() == true` → posts `Notification.Name.accessibilityPermissionGranted`.
AppDelegate observes this and calls `window.makeKeyAndOrderFront(nil)` +
`NSApp.activate(ignoringOtherApps: true)` — window jumps back to front automatically.

`NSApp.activate` from within a Swift Task was unreliable (Swift 5 mode, cooperative
threading). Using `NotificationCenter` + AppDelegate-side handler (guaranteed main
thread) is the reliable approach.

### Toggle collapsing to zero height
SwiftUI `Toggle` inside nested `VStack` was rendering with zero height on macOS.
Fixed by using a flat `HStack` row with explicit `.toggleStyle(.switch)`.

---

## 12. Stale SPM Build Cache — Silent No-Op Builds

### Problem
All UI changes after some point were silently not being deployed. `swift build` was
showing "Build complete (0.30s)" — suspiciously fast. The `.build` binary had an
August 1 timestamp even though source files were modified in October.

**Root cause:** SPM's incremental compilation cache was treating all files as unchanged.
The deploy script was copying the August 1 binary to `/Applications` on every run,
giving it a fresh Oct 12 timestamp but with stale content. Every user complaint about
"still doesn't work" was because the old code was running.

**Fix:** `swift package clean` forced a full 16-second rebuild. After that, the
binary was genuinely updated.

**Secondary fix:** After `swift package clean`, SPM changed output from
`.build/arm64-apple-macosx/debug/MacTrackpadFix` to `.build/out/Products/Debug/MacTrackpadFix`.
Updated `scripts/deploy.sh` to use `find .build -name MacTrackpadFix` to locate the
binary dynamically regardless of SPM output path.

---

## Key Learnings

1. **SPM incremental compilation can silently stale.** If UI changes aren't showing,
   run `swift package clean` before building. The 0.3s build time is the giveaway.

2. **Swift 6 actor isolation fires at the timer callback level, not inside Task.**
   `DispatchQueue.main.async` inside a timer is safe; `Task { @MainActor in }` is not —
   the isolation check fires on the outer C-level callback thread.

3. **CGEventTaps are silently disabled** by macOS without notification. A watchdog
   timer is mandatory for production reliability. 0.5s interval is the right trade-off.

4. **NSWorkspace.frontmostApplication is an XPC call.** Never call it per-event.
   Cache with a TTL (150ms works well).

5. **SMAppService.mainApp does not survive ad-hoc re-signing.** Use LaunchAgent plist
   for unsigned/ad-hoc apps — it's path-based, not signature-based.

6. **postMediaKey per event = stepped volume.** macOS snaps to 6.25% on every key
   event regardless of what CoreAudio was set to. One key at gesture end only.

7. **CVDisplayLink output path changes after `swift package clean`.** Hardcoded paths
   in build scripts will break. Always use `find` to locate build artifacts.

---

## Files Changed (this session, major)

| File | Change |
|---|---|
| `Sources/GestureInterpreter/FlingEngine.swift` | CVDisplayLink + DispatchSourceUserDataAdd coalescing fling |
| `Sources/GestureInterpreter/GestureInterpreter.swift` | Direct delta, lockedTarget, haptic integration |
| `Sources/GestureInterpreter/HapticEngine.swift` | NSHapticFeedbackManager, notch detection, per-target state |
| `Sources/GestureEngine/GestureEngine.swift` | Pinch support, mutex, decision window, watchdog, frontmost cache |
| `Sources/VolumeController/VolumeController.swift` | Split adjustVolume/showHUD |
| `Sources/AppSettings.swift` | HapticLevel, PinchTarget, pinchEnabled, excludedBundleIDs prefix match |
| `Sources/Permissions/OnboardingView.swift` | Launch-at-login toggle, auto-refocus notification |
| `Sources/Utilities/LaunchAtLoginManager.swift` | Replaced SMAppService with LaunchAgent plist |
| `App/AppDelegate.swift` | bringOnboardingToFront, display sleep/wake handlers |
| `scripts/deploy.sh` | Dynamic binary path, Info.plist copy, framework embed |
| `Package.swift` | Swift 5 mode for Core target, Sparkle dependency |
