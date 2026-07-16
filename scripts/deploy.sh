#!/bin/bash
# deploy.sh — Build, sign, and install Mac Trackpad Fix.
# Ad-hoc signing with a stable identifier keeps the TCC trust entry valid
# across binary updates. Run this instead of manually copying the binary.
set -e

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
APP="/Applications/MacTrackpadFix.app"
BINARY="$APP/Contents/MacOS/MacTrackpadFix"
BUILD_BINARY="$WORKSPACE/.build/arm64-apple-macosx/debug/MacTrackpadFix"

echo "→ Building..."
cd "$WORKSPACE"
swift build

echo "→ Stopping running instance..."
pkill -x MacTrackpadFix 2>/dev/null || true
pkill -x TrackpadVolumeKnob 2>/dev/null || true
sleep 0.3

echo "→ Creating app bundle..."
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

echo "→ Copying binary..."
cp "$BUILD_BINARY" "$BINARY"

echo "→ Updating Info.plist..."
cp "$WORKSPACE/MacTrackpadFix/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "→ Copying icon..."
cp "$WORKSPACE/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "→ Embedding Sparkle.framework..."
FRAMEWORKS_DIR="$APP/Contents/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
rm -rf "$FRAMEWORKS_DIR/Sparkle.framework"
cp -R "$WORKSPACE/.build/arm64-apple-macosx/debug/Sparkle.framework" "$FRAMEWORKS_DIR/"

echo "→ Ad-hoc signing (stable identity across updates)..."
install_name_tool -add_rpath @executable_path/../Frameworks "$BINARY" 2>/dev/null || true
codesign --force --sign - --preserve-metadata=identifier,entitlements "$BINARY"
codesign --force --deep --sign - "$APP"

echo "→ Launching..."
open "$APP"

echo "✓ Done. If gestures don't work, click 'Re-check Permissions' in the menu bar."
