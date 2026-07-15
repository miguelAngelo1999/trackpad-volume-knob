#!/bin/bash
# sign_release.sh — Sign a release ZIP with Sparkle ed25519 and update appcast.xml
# Run from your terminal (not from Kiro) because it needs keychain access.
#
# Usage:
#   ./scripts/sign_release.sh 1.1.0

set -e

VERSION="${1:-1.1.0}"
WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_BIN="$WORKSPACE/.build/artifacts/sparkle/Sparkle/bin"
ZIP="$WORKSPACE/TrackpadVolumeKnob-${VERSION}.zip"

if [ ! -f "$ZIP" ]; then
    echo "ERROR: ZIP not found: $ZIP"
    exit 1
fi

echo "→ Signing $ZIP ..."
SIG=$("$SPARKLE_BIN/sign_update" "$ZIP")
SIZE=$(stat -f %z "$ZIP")

echo ""
echo "Signature: $SIG"
echo "File size: $SIZE"
echo ""
echo "Now update appcast.xml — replace the <enclosure> attributes:"
echo "  sparkle:edSignature=\"$SIG\""
echo "  length=\"$SIZE\""
echo "  url=\"https://github.com/miguelAngelo1999/trackpad-volume-knob/releases/download/v${VERSION}/TrackpadVolumeKnob-${VERSION}.zip\""
