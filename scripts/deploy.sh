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

echo "→ Updating Info.plist..."
cp "$WORKSPACE/TrackpadVolumeKnob/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "→ Embedding Sparkle.framework..."
FRAMEWORKS_DIR="$APP/Contents/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
# Remove old copy if present, then copy fresh from build artifacts
rm -rf "$FRAMEWORKS_DIR/Sparkle.framework"
cp -R "$WORKSPACE/.build/arm64-apple-macosx/debug/Sparkle.framework" "$FRAMEWORKS_DIR/"

echo "→ Ad-hoc signing (stable identity across updates)..."
# Add rpath for embedded Sparkle.framework
install_name_tool -add_rpath @executable_path/../Frameworks "$BINARY" 2>/dev/null || true
# --preserve-metadata=identifier keeps the bundle identifier as the signing identity
# so TCC sees the same identifier every time and doesn't invalidate trust.
codesign --force --sign - --preserve-metadata=identifier,entitlements "$BINARY"
codesign --force --deep --sign - "$APP"

echo "→ Launching..."
open "$APP"

echo "✓ Done. If gestures don't work, click 'Re-check Permissions' in the menu bar."
