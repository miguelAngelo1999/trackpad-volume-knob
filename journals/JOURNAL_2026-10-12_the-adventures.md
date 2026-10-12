# Journal — 2026-10-12 — The Adventures: Wrong Turns, Dead Ends, and Eureka Moments

A narrative account of what actually happened during this session —
the attempts that failed, the theories that were wrong, and the moments
where the real answer finally showed up.

---

## Adventure 1: The Flywheel That Kept Crashing

We wanted fling momentum — the mac-mouse-fix physics where a fast rotation
keeps coasting after your fingers lift. Simple idea. Should take an hour.

It took most of the morning.

**Attempt 1:** Ported `DragInertiaEngine` directly with a `DispatchSourceTimer`
firing at 120Hz and dispatching to main via `Task { @MainActor in ... }`.
App crashed immediately on first rotation with `SIGTRAP`. Stack:
```
_dispatch_assert_queue_fail → _swift_task_checkIsolatedSwift
→ closure #1 in FlingEngine.startFlywheelTimer()
```

Read the crash, added `@MainActor` to `FlingEngine`. Same crash.

**Attempt 2:** Removed `@MainActor`, marked callbacks `@Sendable`, added
`nonisolated(unsafe)`. Compiler screamed `SendingRisksDataRace` on every closure.
Fought the type system for an hour trying different combinations of
`@Sendable`, `nonisolated`, `MainActor.assumeIsolated`. Each fix surfaced
a new error. The compiler was winning.

**Attempt 3:** Switched to `DispatchQueue.main.async` instead of `Task`.
Different crash. The Swift 6 runtime STILL fired the assertion — on the
OUTER timer callback closure, not inside the async block.

At this point we'd tried the same approach three times with minor variations.
Classic failure loop. Stepped back.

**Eureka:** The real problem wasn't the callback pattern — it was the
Swift language mode. Swift 6 injects `dispatch_assert_queue` checks
at every `@MainActor` call site at the CALL LEVEL, not at execution time.
A C-level DispatchSourceTimer callback that enqueues anything to the main
actor trips the check regardless of whether you wrapped it in async or not.

Fix: `.swiftLanguageMode(.v5)` for the core target. The threading is safe
by construction. Swift 6 just can't prove it statically from a GCD timer.
One line in Package.swift. App ran. Three hours gone.

---

## Adventure 2: Volume Jittering Everywhere

After the crash was fixed, volume was visibly jittering — jumping backward
mid-rotation. Logs showed multiple thread IDs writing to CoreAudio at the
same time.

**Wrong theory 1:** "The fling timer is still running from a previous gesture."
Added cancel logic, checked lifetimes. Timer was cancelling correctly.

**Wrong theory 2:** "The flywheel is accumulating too much velocity."
Tuned the drag coefficient. Made it feel worse.

**Actual cause:** Found in the logs — thread IDs `b46a7d`, `b46a7e`, `b46a81`
ALL writing volume at the same timestamps. The 120Hz flywheel was queuing
`DispatchQueue.main.async` blocks faster than the main queue could drain them.
Each one read `currentVolume`, computed a new value, wrote it. But by the time
block N ran, block N-1 had already changed `currentVolume` to something different.
Classic TOCTOU race on a supposedly single-threaded queue.

**Eureka:** The flywheel was wrong for this use case entirely. Mouse dragging
needs a flywheel because the input is continuous. Trackpad rotation events
ARE the input — there's no gap to fill. During the gesture, apply deltas
directly from events (synchronous, zero latency, zero races). Only AFTER
fingers lift does a fling timer make sense. Deleted the flywheel completely.
Volume went smooth immediately.

---

## Adventure 3: Volume Still Moving In Steps

Rotation was smooth now, but volume still jumped in discrete 6.25% increments.
Tried adjusting sensitivity, degreesPerStep, acceleration. Nothing changed
the stepping behavior.

Stared at the code for a while. `adjustVolume(by:)` was writing CoreAudio
correctly. Values were smooth in the logs. But the HUD showed discrete steps.

**Wrong theory:** "The HUD is quantizing the display."
Checked HUD code. It was just displaying `currentVolume * 100`. Not the issue.

**Actual cause:** `postMediaKey` was being called on EVERY event.
Each call posts `NX_KEYTYPE_SOUND_UP` or `NX_KEYTYPE_SOUND_DOWN` —
equivalent to pressing F11 or F12. macOS responds to each key event by
snapping the volume to the nearest 6.25% increment (1/16 of the range),
OVERWRITING the smooth CoreAudio value we just set.

So the pipeline was:
1. CoreAudio write: 47.3% ✓
2. Media key post: macOS says "that's 7/16, so actually 43.75%" ✗

Called 50 times per second.

**Eureka:** `postMediaKey` once at gesture END, not per event.
The HUD reads the current CoreAudio value (which is already correct),
so it displays the right level. The key just tells macOS "hey, show the HUD."
Volume became perfectly smooth.

---

## Adventure 4: The Mystery of the Silent Crash

After weeks of use, the user started reporting the app "silently crashes."
No crash report. No error. Gestures just stopped working.

**Wrong theory 1:** "TCC trust expired."
Checked TCC. `auth_value = 2` (granted). `AXIsProcessTrusted()` returned
true from the swift interpreter.

**Wrong theory 2:** "The CGEventTap is being disabled."
Added a 5-second watchdog. Gestures recovered every 5 seconds.
But WHY was the tap being disabled?

**Debug attempt:** Watched `log stream` for our subsystem. Zero output.
Expanded to all of WindowServer/SkyLight/CGEventTap. Checked for "tap disabled"
messages. Nothing useful.

**Wrong theory 3:** "CVDisplayLink is leaking and crashing."
Added generation counters, improved cleanup. Memory improved slightly.
Crashes continued.

**Actual cause (weeks of use to find):** Found when checking memory growth.
App was at 198MB (started at 70MB) after a long session.
`NSWorkspace.shared.frontmostApplication` was being called on EVERY gesture
event — 50+ XPC round-trips per second. Each returns an `NSRunningApplication`
object. ARC was not draining them fast enough. The main queue backed up.
When the main run loop was too busy, the CGEventTap's run loop source
couldn't fire promptly. macOS detected the latency and disabled the tap.

**Eureka:** Cache `frontmostBundleID()` with 150ms TTL.
XPC calls dropped from 50+/sec to ~7/sec. Memory stabilized at 69MB.
The tap stayed enabled. The 0.5s watchdog is still there as a safety net,
but it rarely fires now.

---

## Adventure 5: The Pinch/Rotation Confusion

Added pinch-to-brightness. Worked beautifully on maps and photos. Then user
said: "rotating for volume is also changing brightness."

**First diagnosis (wrong):** "The exclusion list isn't blocking Chrome."
Checked. Chrome WAS in the list... for stable Chrome (`com.google.Chrome`).
Chrome Beta (`com.google.Chrome.beta`) wasn't. Fixed with prefix matching.

Problem reported again. Still happening, in a different app this time.

**Actual cause:** macOS fires BOTH `.rotate` AND `.magnify` events at gesture
start — even for a pure rotation. The first few frames always have a small
magnification component as fingers settle. Our app was acting on both.

**Failed fix 1:** Velocity gate — fast pinch = brightness, slow = ignore.
Tested. Hard to tune. Slow deliberate rotations still triggered it.

**Failed fix 2:** "Can we read console logs to detect if the app is zooming?"
Ran `log stream` during a pinch-zoom in Safari. Zero zoom-related output.
Ran it during Chrome zoom. Also nothing. GPU compositor handles it silently.
Confirmed empirically: no log-based detection possible.

**Eureka:** Mutual exclusion + decision window. Once a rotation commits,
suppress all magnify events until it ends. In the first 80ms, accumulate
both signals and commit to whoever has the higher normalized score.
Rotation almost always wins because it has a larger normalized magnitude
in the first few events. Pinch needs to also pass a minimum 0.015 threshold.
Rotation-during-brightness-attempt: gone. Clean pinch: still works.

---

## Adventure 6: The Launch at Login That Never Launched

User enabled "Launch at login." App never launched at login.

**Wrong theory:** "The toggle isn't saving."
Checked. `launchAtLogin = 1` in UserDefaults. Setting was saving fine.

**Wrong theory:** "LaunchAtLoginManager.setEnabled is failing silently."
Added error logging. No error. `SMAppService.mainApp.register()` returned
success. `SMAppService.mainApp.status` showed `.enabled`.

But the app never launched at login. Ever.

Tried reboot. Tried re-enabling. Tried checking system login items.
The app wasn't there. The setting was "on," macOS said it was registered,
but nothing happened.

**Eureka:** Found by checking status from a fresh context.
`SMAppService.mainApp.status` returned `.notFound` (rawValue 3) — not `.enabled`.
The discrepancy: `register()` succeeds and immediately returns `.enabled`.
But every time `deploy.sh` runs — which does `codesign --sign - ...` — the
ad-hoc signing identity changes. `SMAppService` is tied to the signing identity,
not just the bundle ID. Each re-sign de-registered the login item silently.
The setting showed "on" because UserDefaults was correct, but the actual
system registration was gone.

Fix: `~/Library/LaunchAgents/com.trackpadvolumeknob.plist`. Path-based.
Not signature-based. The plist just says "run this binary at this path."
It doesn't care what the binary is signed with. Survived 20+ redeployments
in testing without breaking once.

---

## Adventure 7: The UI Change That Was Never There

The longest-running invisible bug of the session.

User said "launch at login toggle isn't in the onboarding." Added it.
User tested. "Still doesn't show." Checked the code. Code was correct.
Rebuilt. Redeployed. "Still not there."

This happened THREE TIMES across multiple sessions. Every time:
1. Write the code
2. `swift build` → "Build complete (0.30s)"
3. Deploy
4. Old UI still showing

Checked file contents. Code was correct. Checked the binary. `strings` failed.

**First wrong theory:** "Window is too short (440px). Content is clipped."
Bumped to 580px. Added ScrollView. Redeployed. Same old UI.

**Second wrong theory:** "SwiftUI Toggle has a layout issue."
Rewrote with explicit `HStack`, `.toggleStyle(.switch)`. Redeployed. Same.

**Third attempt:** Noticed something. After `swift build` prints
"Build complete (0.30s)" — fast builds used to take 2-3 seconds.
Checked the binary timestamp in `.build/`: August 1. Today is October 12.
The binary in `.build` had NOT been updated despite "Build complete" printing.

Checked `/Applications/MacTrackpadFix.app`: October 12 timestamp.
Checked content: `strings` found no "Launch at login" text. August content.

**Eureka (finally):** SPM's incremental compilation had stale cache entries.
It thought `OnboardingView.swift` was unchanged (perhaps because the file was
modified by `str_replace` tool in a way that didn't update the mtime correctly,
or because SPM's dependency tracking file was out of date). "Build complete"
was technically true — nothing needed to be built, from SPM's perspective.

`swift package clean` forced a full 16-second rebuild. The binary updated.
The UI was there. The toggle had been coded correctly the first time, three
sessions ago. The stale cache had been invisibly blocking it the whole time.

**Bonus bug:** After `swift package clean`, SPM changed its output path from
`.build/arm64-apple-macosx/debug/MacTrackpadFix` to
`.build/out/Products/Debug/MacTrackpadFix`. The deploy script had the path
hardcoded. It now fails with "file not found." Fixed by using `find` to
locate the binary dynamically.

---

## Patterns Worth Remembering

**"It's the cache."**
Two times this session: once with SPM's incremental build, once with
`NSWorkspace.frontmostApplication`. When something should be changing but
isn't, check every cache in the pipeline.

**"Two failed attempts = step back, don't patch."**
The flywheel crash, the toggle not showing — both wasted time with incremental
patches to a fundamentally wrong approach. The right answer was always one
level of abstraction up.

**"Verify on the actual target."**
`AXIsProcessTrusted()` returning `true` from the swift REPL meant nothing.
`strings` not finding text in a binary told us something was deeply wrong.
Always verify against the actual running artifact, not a proxy.

**"Build times are diagnostic data."**
0.3s `swift build` = stale cache, nothing really compiled.
16s `swift build` = fresh build, binary actually updated.
The number matters.

**"The console confirms the absence."**
Three separate attempts to find a log signal for pinch-to-zoom across three
different logging levels and processes. The absence of output WAS the answer —
GPU compositor is silent by design.

---

*The app works now. It took longer than it should have.
That's software.*
