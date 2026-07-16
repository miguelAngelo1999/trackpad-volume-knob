#!/bin/bash
# build_pkg.sh — Build a .pkg that installs Mac Trackpad Fix
# and migrates from TrackpadVolumeKnob (renames app, clears old TCC entry).
# Uses ad-hoc signing (no paid Developer ID required).
# Account: migangelo1999@gmail.com (Z34866BMSZ)
#
# Usage: ./scripts/build_pkg.sh 2.0.0
# Produces: MacTrackpadFix-2.0.0.pkg

set -e

VERSION="${1:-2.0.0}"
WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
APP="$WORKSPACE/MacTrackpadFix.app"
PKG_OUT="$WORKSPACE/MacTrackpadFix-${VERSION}.pkg"
SCRIPTS_DIR="$WORKSPACE/scripts/pkg_scripts"

# Validate app bundle exists
if [ ! -d "$APP" ]; then
    echo "ERROR: $APP not found. Run 'swift build -c release' and assemble the app first."
    exit 1
fi

echo "→ Preparing package scripts..."
rm -rf "$SCRIPTS_DIR"
mkdir -p "$SCRIPTS_DIR"

# Copy postinstall script and make executable
cp "$WORKSPACE/scripts/postinstall" "$SCRIPTS_DIR/postinstall"
chmod +x "$SCRIPTS_DIR/postinstall"

echo "→ Building component package..."
pkgbuild \
    --root "$APP" \
    --install-location "/Applications/Mac Trackpad Fix.app" \
    --scripts "$SCRIPTS_DIR" \
    --identifier "com.trackpadvolumeknob" \
    --version "$VERSION" \
    "$WORKSPACE/MacTrackpadFix-component-${VERSION}.pkg"

echo "→ Building product package..."
productbuild \
    --package "$WORKSPACE/MacTrackpadFix-component-${VERSION}.pkg" \
    "$PKG_OUT"

# Clean up intermediate
rm -f "$WORKSPACE/MacTrackpadFix-component-${VERSION}.pkg"
rm -rf "$SCRIPTS_DIR"

echo ""
echo "✓ Built: $PKG_OUT ($SIZE bytes)"
echo ""
echo "Next steps:"
echo "  1. Sign for Sparkle (run in terminal — needs keychain access):"
echo "     .build/artifacts/sparkle/Sparkle/bin/sign_update $PKG_OUT"
echo ""
echo "  2. Update appcast.xml with the signature, length ($SIZE), and url"
echo "  3. Upload to GitHub Releases as MacTrackpadFix-${VERSION}.pkg"
