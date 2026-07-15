# Trackpad API Research Report
## TrackpadVolumeKnob — macOS Rotation Gesture Methods

---

## 1. Public APIs

### 1a. `NSEvent.addGlobalMonitorForEventsMatchingMask(.rotate)`

**Status: ✅ Works — PRIMARY APPROACH**

AppKit exposes `NSEvent.addGlobalMonitorForEventsMatchingMask(_:handler:)` which delivers
copies of events dispatched to *other* applications. Using the `.rotate` mask (which maps
to `NSEventTypeRotate`, internal type 18) gives real-time rotation deltas as the user
performs the two-finger rotation gesture.

```swift
NSEvent.addGlobalMonitorForEventsMatchingMask([.rotate]) { event in
    let degrees = event.rotation  // Float, positive = clockwise
}
```

**Key properties on `NSEvent` for rotation:**
- `event.rotation` — delta in degrees since last event
- `event.phase` — `.began / .changed / .ended / .cancelled`
- `event.timestamp` — system uptime at event delivery

**Limitations:**
- Requires **Accessibility** permission (Privacy › Accessibility in System Settings).
  On macOS 10.15+, also appears under Input Monitoring.
- Receives a *copy* — cannot suppress or modify the event (cannot prevent macOS from
  also acting on the gesture, e.g. rotating images in Preview).
- Not available in sandboxed App Store apps without special entitlement review.

**Required permissions:** Accessibility

---

### 1b. `NSRotationGestureRecognizer`

**Status: ⚠️ Partial — in-window only**

`NSRotationGestureRecognizer` is attached to an `NSView` and only fires for gestures
that occur *within that view*. There is no global equivalent at the `NSGestureRecognizer`
level.

**Not suitable** for a menu bar app that must intercept gestures over other apps.

---

### 1c. Accessibility (AX) APIs

**Status: ❌ Not applicable for input**

The Accessibility API (`AXUIElement`, `AXObserver`) is designed for reading and
controlling UI elements, not for capturing raw input events. It cannot deliver rotation
gesture data.

---

## 2. Low-Level APIs

### 2a. CGEventTap

**Status: ✅ Works with caveats**

`CGEventTap` can intercept events at the HID (hardware) or session level. However,
trackpad gesture events (rotate, magnify, swipe) are generated at the *Cocoa layer*
and do **not** have a corresponding `kCGEventType` constant. The raw type integer (29
for gesture events) can be matched with `kCGEventTypeGesture`, but the event data must
be decoded with private field accessors.

The practical advantage over the NSEvent global monitor is the ability to *consume*
events (prevent them from reaching other apps). For volume control this is unnecessary
and adds complexity.

**Requires:** Accessibility permission (same as NSEvent monitor).

**Verdict:** Offers no benefit over NSEvent global monitor for this use case. Adds
complexity and uses undocumented event field IDs.

---

### 2b. IOKit

**Status: ❌ Not viable for high-level gesture recognition**

IOKit provides access to raw HID (Human Interface Device) reports. Reading raw trackpad
data via IOKit delivers individual finger contact points as HID reports, not interpreted
gestures. Computing a rotation gesture from raw multi-finger data requires implementing
the gesture-recognition algorithm from scratch (tracking contact centroid, angles, etc.).

This is approximately what `MultitouchSupport.framework` does internally.

**Verdict:** Only necessary if targeting hardware with no OS gesture layer (embedded
systems). Far too complex and fragile for a standard macOS utility.

---

## 3. Private Frameworks

### 3a. `MultitouchSupport.framework`

**Status: ✅ Works — NOT RECOMMENDED for distribution**

Located at:
```
/System/Library/PrivateFrameworks/MultitouchSupport.framework
```

Exposes C callbacks for raw multitouch contact data per frame:
```c
typedef int (*MTContactCallbackFunction)(int device, MTTouch* data, int nTouches, double timestamp, int frame);
void MTRegisterContactFrameCallback(MTDeviceRef device, MTContactCallbackFunction callback);
```

Each `MTTouch` carries normalized x/y position, velocity, size, and a unique finger ID.
A rotation gesture can be computed by tracking the angular change of the vector between
two contact points across frames.

**Open-source wrappers:**
- [Kyome22/OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) — Swift package
- [mhuusko5/M5MultitouchSupport](https://github.com/mhuusko5/M5MultitouchSupport)

**Advantages:**
- No Accessibility permission required.
- Delivers data before the OS gesture recognizer fires — lower latency.
- Works when the trackpad is being used over apps that consume/cancel gesture events.

**Limitations:**
- **Private framework** — may break on any macOS update.
- Not allowed in Mac App Store submissions.
- Requires loading the framework by path (`dlopen`), which is blocked in hardened runtimes
  without a special entitlement.
- Apple Silicon + recent macOS versions have tightened restrictions on private framework access.

**Verdict:** Powerful but fragile. Best left as a future opt-in for power users.

---

## 4. Comparison Table

| Method | Works globally | Permission | Can consume | App Store | Stability | Complexity |
|---|---|---|---|---|---|---|
| NSEvent `.rotate` global monitor | ✅ | Accessibility | ❌ | ⚠️ (entitlement) | ✅ High | Low |
| CGEventTap (gesture type) | ✅ | Accessibility | ✅ | ⚠️ | ✅ High | Medium |
| NSRotationGestureRecognizer | ❌ (in-window only) | None | ✅ | ✅ | ✅ High | Low |
| IOKit HID raw data | ✅ | None* | ✅ | ❌ | ⚠️ Medium | Very High |
| MultitouchSupport.framework | ✅ | None | ✅ | ❌ | ⚠️ Low | High |

*IOKit requires `com.apple.security.device.usb` or similar entitlements for sandboxed apps.

---

## 5. BetterTouchTool Comparison

BetterTouchTool's "Rotate Gesture" action almost certainly uses one or both of:
1. The `NSEvent` global monitor (for the high-level interpreted gesture)
2. `MultitouchSupport.framework` (for raw per-finger data enabling custom gesture detection)

The `NSEvent` monitor approach matches the *feel* of BTT's rotation gesture: it receives
the OS-interpreted rotation delta in degrees, already smoothed by the system gesture
recognizer. This means the gesture activation threshold, the two-finger interpretation,
and anti-jitter smoothing are all handled by macOS — identical to how BTT experiences it.

---

## 6. Chosen Approach

**Primary:** `NSEvent.addGlobalMonitorForEventsMatchingMask(.rotate)`

Reasons:
- Public, documented API.
- Identical gesture quality to BTT.
- Simple integration — single callback, degrees provided directly.
- Stable across macOS versions.
- Only one permission required (Accessibility).

**Fallback mode:** Modifier-key gating (Option/Control/Fn + rotate) for users who
prefer not to grant broad Accessibility access or want intentional activation.

**Future extension:** `MultitouchSupport.framework` via `OpenMultitouchSupport` can be
added as an optional advanced mode for lower-latency or permission-free operation once
the API stabilises on Apple Silicon.

---

## 7. Required Permissions Summary

| Permission | Why | Where in System Settings |
|---|---|---|
| **Accessibility** | `NSEvent` global monitor for gesture events | Privacy & Security › Accessibility |

No microphone, camera, location, contacts, or network permissions are required.
