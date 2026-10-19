#!/bin/bash
# deploy.sh — Build, sign, and install Mac Trackpad Fix.
# Ad-hoc signing with a stable identifier keeps the TCC trust entry valid
# across binary updates. Run this instead of manually copying the binary.
set -e

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
APP="/Applications/MacTrackpadFix.app"
BINARY="$APP/Contents/MacOS/MacTrackpadFix"

# Find the built binary wherever SPM puts it (path changed between toolchain versions)
BUILD_BINARY=$(find "$WORKSPACE/.build" -name "MacTrackpadFix" -type f \
    -not -path "*.dSYM*" -not -path "*GestureTest*" \
    | sort -t/ -k1,1 | tail -1)

if [ -z "$BUILD_BINARY" ]; then
    echo "ERROR: Could not find MacTrackpadFix binary in .build/"
    exit 1
fi

# Derive Sparkle.framework path from the same directory as the binary
SPARKLE_FRAMEWORK="$(dirname "$BUILD_BINARY")/Sparkle.framework"

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
if [ -d "$SPARKLE_FRAMEWORK" ]; then
    cp -R "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/"
else
    echo "⚠ Sparkle.framework not found beside binary — skipping"
fi

echo "→ Ad-hoc signing (stable identity across updates)..."
install_name_tool -add_rpath @executable_path/../Frameworks "$BINARY" 2>/dev/null || true
# Force the bundle identifier as the signing identity so TCC always sees com.trackpadvolumeknob
codesign --force --sign - --identifier "com.trackpadvolumeknob" "$BINARY"
codesign --force --deep --sign - --identifier "com.trackpadvolumeknob" "$APP"

echo "→ Launching..."
open "$APP"

echo "✓ Done. If gestures don't work, click 'Re-check Permissions' in the menu bar."
