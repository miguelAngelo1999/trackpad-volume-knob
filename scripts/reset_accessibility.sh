#!/bin/bash
# Removes the stale TCC accessibility entry for TrackpadVolumeKnob so macOS
# re-evaluates the current binary on next launch.
# Run once after replacing the binary in /Applications.

BUNDLE_ID="com.trackpadvolumeknob"
APP_PATH="/Applications/TrackpadVolumeKnob.app"

echo "Removing stale TCC entry for $BUNDLE_ID..."
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null && echo "Done." || echo "Nothing to reset (may need sudo for system TCC db)."

echo ""
echo "Re-registering with AXIsProcessTrustedWithOptions..."
# Open the app briefly so it re-prompts / re-registers
open "$APP_PATH"
echo "Check System Settings > Privacy & Security > Accessibility and re-enable if needed."
