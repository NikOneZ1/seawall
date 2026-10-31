#!/bin/bash
# Builds build/Seawall.app from the Swift package. No Xcode needed — Command Line Tools are enough.
#
#   scripts/build-app.sh            # release build, ad-hoc signed
#   SIGN_IDENTITY="Apple Development: …" scripts/build-app.sh
#   HARDENED_RUNTIME=1 SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
#
# HARDENED_RUNTIME=1 (used by scripts/make-dmg.sh) signs with the hardened runtime, a secure
# timestamp and Resources/Seawall.entitlements, as notarization requires. Without it the
# signing step is exactly what it always was.
#
# With ad-hoc signing macOS asks for Safari access again after every rebuild;
# a real signing identity keeps the permission.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
IDENTITY="${SIGN_IDENTITY:--}"
APP="build/Seawall.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Seawall" "$APP/Contents/MacOS/Seawall"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [ "${HARDENED_RUNTIME:-0}" = "1" ]; then
    if [ "$IDENTITY" = "-" ]; then
        echo "HARDENED_RUNTIME=1 needs a real SIGN_IDENTITY; ad-hoc signatures can't be timestamped or notarized." >&2
        exit 1
    fi
    codesign --force --sign "$IDENTITY" --options runtime --timestamp \
        --entitlements Resources/Seawall.entitlements "$APP"
else
    codesign --force --sign "$IDENTITY" "$APP"
fi

echo "Built $APP"
