# TrackpadVolumeKnob — User Guide

Turn your MacBook or Magic Trackpad into a physical volume and brightness knob. Place two fingers on the trackpad and rotate them clockwise to raise volume, counter-clockwise to lower it.

---

## Installation

1. Copy `TrackpadVolumeKnob.app` to your `/Applications` folder.
2. Open it. An onboarding window will appear asking for one permission.
3. Click **First-time Setup** → grant Accessibility in System Settings → come back and click **Get Started**.
4. The app lives in your menu bar (speaker icon). It starts working immediately.

### After updating the app

Every time the binary is replaced (new version, re-built from source), macOS invalidates the Accessibility trust because the code signature hash changed. The app detects this and shows the onboarding window automatically.

Click **Reset & Re-authorize** — it clears the stale entry and opens System Settings directly to the Accessibility list. Toggle the switch next to TrackpadVolumeKnob off and back on, then click **Get Started**.

---

## Basic Usage

| Gesture | Result |
|---|---|
| Two-finger rotate clockwise | Volume / brightness up |
| Two-finger rotate counter-clockwise | Volume / brightness down |
| Fast flick then lift | Momentum coast continues after your fingers leave the trackpad |

The native macOS HUD (the floating bar that appears when you press F11/F12) shows the current volume level. For external display brightness a compact overlay appears on that display.

---

## Settings

Open Settings from the menu bar icon → **Settings…** (or press ⌘,).

### General tab

| Setting | What it does |
|---|---|
| Launch at login | Starts the app automatically when you log in |
| Show menu bar icon | Toggle the speaker icon in the menu bar |
| Enable debug logging | Prints verbose messages to Console.app (useful for troubleshooting) |

### Gestures tab

**Sensitivity** — the "Volume per step" slider sets how much volume changes per degree of rotation. Higher = more sensitive. Default 5%.

**Degrees per step** — how many degrees of rotation equals one sensitivity unit. Lower = more sensitive. Default 5°. In practice: at default settings, rotating 180° sweeps the full 0–100% range.

**Invert rotation direction** — swap clockwise/counter-clockwise behaviour.

**Dead zone** — degrees of rotation ignored at the start of each gesture. Prevents accidental bumps from triggering changes. Default 1.5°.

**Acceleration** — at higher values, fast rotations produce larger jumps while slow precise rotations stay small. Set to 1.0× for completely linear response. Default 2.0×.

**Haptic Feedback** — Force Touch trackpad feedback while rotating:

| Level | Volume feel | Brightness feel |
|---|---|---|
| Off | Silent | Silent |
| Light | Subtle tick on every change | Subtle tick on every change |
| Medium | Snap on every change + bump at 10%, 20%… | Gentle tick + softer bump at brightness steps |
| Strong | Firm click on every change + notch bumps | Snap + softer notch bumps |

**Fallback Mode** — when enabled, the gesture only works while holding a chosen modifier key (Fn, Control, Option, or ⌘). Useful if you want rotation to feel intentional rather than always-on.

**Rotation controls** — choose whether rotation adjusts Volume or Brightness by default.

**Hold modifier to switch to…** — assign a modifier key (Control, Option, etc.) that temporarily switches the target while held. For example: base target = Volume, modifier = Control → hold Control while rotating to adjust brightness instead.

### Audio tab

Shows which output device is being controlled (always the macOS default output). Contains a test slider to verify volume control is working.

### Apps tab

Some apps use the two-finger rotation gesture natively (rotating a map in Maps, rotating an image in Preview, spinning a 3-D model in SketchUp). When one of these apps is frontmost, TrackpadVolumeKnob steps aside and lets the gesture pass through untouched.

The list comes pre-populated with 22 known apps. You can:

- **Hover** over any row to reveal the remove (−) button.
- Click **Add App** to type in a bundle ID manually.
- Click **Add Frontmost App** — switch to any app, come back here, and click this button to add it in one click.
- Click **Reset to Defaults** to restore the built-in list.

To find an app's bundle ID: open Terminal and run `osascript -e 'id of app "AppName"'`.

### Appearance tab

Switches the settings window between System, Light, and Dark appearance.

---

## Menu Bar

Click the speaker icon in the menu bar:

| Item | What it does |
|---|---|
| Settings… | Opens the settings window |
| Re-check Permissions | Re-verifies Accessibility trust. Shows onboarding if permission was revoked. |
| Quit TrackpadVolumeKnob | Stops the app |

---

## Troubleshooting

**Gestures don't do anything**

1. Click **Re-check Permissions** in the menu bar.
2. If the onboarding window appears, click **Reset & Re-authorize** and re-enable in System Settings.
3. Make sure the frontmost app is not in the Apps exclusion list.

**Volume changes are going the wrong direction**

Open Settings → Gestures → enable **Invert rotation direction**.

**Changes are too sensitive / not sensitive enough**

Adjust **Degrees per step** (lower = more sensitive) and **Sensitivity** (higher = bigger jumps). The two sliders work together.

**Fling / momentum doesn't trigger after a quick flick**

The fling requires the fingers to be moving when they lift. Very slow lifts don't trigger it. Try finishing the rotation with a deliberate flick. The fling detects speed from the last ~200ms of movement.

**App doesn't start at login**

Open Settings → General → enable **Launch at login**. If it still doesn't start, check System Settings → General → Login Items and ensure TrackpadVolumeKnob is listed and enabled.

**The brightness control only affects the built-in screen**

Ensure your cursor is on the external display when you rotate. Brightness always adjusts whichever display the cursor is on at the time of the gesture.

---

## Privacy

TrackpadVolumeKnob requests exactly one permission:

- **Accessibility** — required to receive rotation gesture events from the OS while other apps are in focus. Without this, `NSEvent.addGlobalMonitorForEvents` returns nothing.

No network requests are made. No data leaves your machine. No analytics, no telemetry.
