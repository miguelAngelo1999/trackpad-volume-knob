# Mac Trackpad Fix — User Guide

Turn your MacBook or Magic Trackpad into a physical volume and brightness knob. Place two fingers on the trackpad and rotate or pinch to control volume and brightness — no buttons, no shortcuts, just gesture.

---

## Installation

### Via automatic update (existing TrackpadVolumeKnob users)

If you had TrackpadVolumeKnob installed, it will update itself automatically within 24 hours. The update renames the app to Mac Trackpad Fix, clears the old Accessibility permission entry, and re-adds the app to the list so you just need to flip the toggle once.

### Fresh install

1. Download `MacTrackpadFix-latest.pkg` from the releases page.
2. Open the `.pkg` — it installs to `/Applications/Mac Trackpad Fix.app` and launches the app automatically.
3. An onboarding window appears. Click **Open System Settings** — the app is already in the Accessibility list, just enable the toggle.
4. Click **Check Again** — the onboarding closes and gestures start working immediately.

The app lives in your menu bar. It has no Dock icon.

---

## After updating

Every time the binary changes (Sparkle update, or rebuilt from source), macOS invalidates the Accessibility trust because the code signature hash changes. Mac Trackpad Fix detects this automatically on first launch by comparing a SHA-256 hash of the binary against the stored hash.

When a change is detected it runs `tccutil reset Accessibility` to clear the stale entry, then shows the onboarding window on next launch. You just flip the toggle again — nothing else needed.

---

## Gestures

| Gesture | Default action |
|---|---|
| Two-finger rotate clockwise | Volume up |
| Two-finger rotate counter-clockwise | Volume down |
| Two-finger pinch (spread) | Brightness up |
| Two-finger pinch (close) | Brightness down |
| Fast flick then lift | Momentum coasts after fingers leave |

**Tips for best results:**
- Both fingers need to maintain contact. If one finger barely touches, the trackpad may not recognize it as a two-finger gesture.
- Index + middle finger tend to work more reliably than thumb + index because they're similar in size and pressure.
- The gesture recognizer requires a brief moment to classify whether you're rotating or pinching — the first ~60ms is a disambiguation window.

---

## Settings

Open via menu bar icon → **Settings…** (or ⌘,).

### General

| Setting | Description |
|---|---|
| Launch at login | Starts the app when you log in |
| Show menu bar icon | Toggle the speaker icon in the menu bar |
| Automatically check for updates | Daily Sparkle update checks |
| Enable debug logging | Verbose output in Console.app |

### Gestures

**Sensitivity** — how much volume/brightness changes per degree. Higher = more sensitive. Default 5%.

**Degrees per step** — degrees of rotation per sensitivity unit. Lower = more sensitive. Default 5°. At defaults, 180° sweeps 0–100%.

**Invert rotation direction** — swap clockwise/counter-clockwise.

**Dead zone** — degrees ignored at gesture start to absorb accidental bumps. Default 1.5°.

**Acceleration** — at higher values, fast rotations jump further while slow rotations stay precise. 1.0× = linear. Default 2.0×.

**Haptic Feedback** — Force Touch trackpad feedback:

| Level | Feel |
|---|---|
| Off | No feedback |
| Light | Subtle tick on every change |
| Medium | Snap on every change + bump at each 10% step |
| Strong | Firm click on every change + notch bumps |

**Fallback Mode** — when enabled, gestures only fire while holding a chosen modifier key (Fn, Control, Option, Command). Useful for intentional activation.

**Rotation controls** — choose whether rotation adjusts Volume or Brightness by default.

**Hold modifier to switch** — assign a modifier key to temporarily swap the rotation target while held. E.g. base = Volume, modifier = Control → hold Control while rotating to control brightness instead.

**Pinch Gesture** — enable/disable pinch. When enabled, choose whether pinch controls Brightness or Volume.

### Audio

Shows the current macOS default output device. Contains a test slider to verify volume control is working.

### Apps (Pass-through list)

Some apps use the rotation gesture natively — Maps (rotating a map), Preview (rotating an image), SketchUp (3-D orbit). When one of these apps is frontmost, Mac Trackpad Fix steps aside and passes the gesture through untouched.

The list ships with 22 presets. You can:
- **Hover** any row → click the (−) button to remove it
- **Add App** → type a bundle ID manually
- **Add Frontmost App** → switch to any app, come back, click this to add it in one click
- **Reset to Defaults** → restore the built-in 22 apps

To find a bundle ID: `osascript -e 'id of app "AppName"'`

### Appearance

Switch the settings window between System, Light, and Dark.

---

## Menu Bar

| Item | Action |
|---|---|
| Settings… | Open preferences (⌘,) |
| Check for Updates… | Manual Sparkle update check |
| Re-check Permissions | Re-verify Accessibility. Shows onboarding if revoked. |
| Quit Mac Trackpad Fix | Stop the app (⌘Q) |

---

## Troubleshooting

**Gestures do nothing**
1. Click **Re-check Permissions** in the menu bar.
2. If the onboarding appears, click **Open System Settings** and enable the toggle.
3. Check that the frontmost app is not in the Apps exclusion list.

**Volume goes the wrong direction**
Settings → Gestures → enable **Invert rotation direction**.

**Too sensitive / not sensitive enough**
Lower **Degrees per step** (more sensitive) or raise it (less sensitive). Adjust **Sensitivity** for overall scaling.

**Pinch is triggering instead of rotate (or vice versa)**
The gesture classifier uses a 4-event window (~60ms) to decide which type you're doing. If rotation is misclassified as pinch, try starting the rotation more decisively. Rotation always takes priority if both gestures fire simultaneously.

**Fling doesn't trigger**
The fling requires your fingers to be moving at lift-off. Try finishing with a deliberate flick. The engine tracks the last ~200ms of velocity.

**External display brightness doesn't work**
Make sure the cursor is on the external display when you rotate. Only the display under the cursor is adjusted. If brightness still doesn't respond, the display may not support DDC — check Console.app with debug logging enabled for `BrightnessControllerDDC` messages.

**App doesn't start at login**
Settings → General → enable **Launch at login**. Also verify: System Settings → General → Login Items → Mac Trackpad Fix is listed and enabled.

---

## Privacy

Mac Trackpad Fix requests exactly one permission:

**Accessibility** — required for `NSEvent.addGlobalMonitorForEvents` to receive gesture events from other apps. Without this, the monitor returns nothing.

No network requests are made except to check for updates (via Sparkle, fetching `appcast.xml` from Google Drive). No data leaves your machine. No analytics, no telemetry.
