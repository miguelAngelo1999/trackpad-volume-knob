#!/bin/bash
# deploy.sh — Build, sign, and install TrackpadVolumeKnob.
# Ad-hoc signing with a stable identifier keeps the TCC trust entry valid
# across binary updates. Run this instead of manually copying the binary.
set -e

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
APP="/Applications/TrackpadVolumeKnob.app"
BINARY="$APP/Contents/MacOS/TrackpadVolumeKnob"
BUILD_BINARY="$WORKSPACE/.build/arm64-apple-macosx/debug/TrackpadVolumeKnob"

echo "→ Building..."
cd "$WORKSPACE"
swift build

echo "→ Stopping running instance..."
pkill -x TrackpadVolumeKnob 2>/dev/null || true
sleep 0.3

echo "→ Copying binary..."
cp "$BUILD_BINARY" "$BINARY"

echo "→ Ad-hoc signing (stable identity across updates)..."
# --preserve-metadata=identifier keeps the bundle identifier as the signing identity
# so TCC sees the same identifier every time and doesn't invalidate trust.
codesign --force --sign - --preserve-metadata=identifier,entitlements "$BINARY"
codesign --force --deep --sign - "$APP"

echo "→ Launching..."
open "$APP"

echo "✓ Done. If gestures don't work, click 'Re-check Permissions' in the menu bar."
