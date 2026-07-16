#!/bin/bash
# assemble_app.sh — Assemble MacTrackpadFix.app from release build output
set -e

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
APP="$WORKSPACE/MacTrackpadFix.app"

echo "→ Assembling MacTrackpadFix.app..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Frameworks"

cp "$WORKSPACE/.build/release/MacTrackpadFix"              "$APP/Contents/MacOS/"
cp "$WORKSPACE/MacTrackpadFix/Resources/Info.plist"        "$APP/Contents/"
cp "$WORKSPACE/AppIcon.icns"                                "$APP/Contents/Resources/"
cp -R "$WORKSPACE/.build/arm64-apple-macosx/release/Sparkle.framework" \
      "$APP/Contents/Frameworks/"

install_name_tool -add_rpath @executable_path/../Frameworks \
    "$APP/Contents/MacOS/MacTrackpadFix" 2>/dev/null || true

codesign --force --sign - --identifier "com.trackpadvolumeknob" \
    "$APP/Contents/MacOS/MacTrackpadFix"
codesign --force --deep --sign - --identifier "com.trackpadvolumeknob" "$APP"

echo "✓ MacTrackpadFix.app assembled and signed"
