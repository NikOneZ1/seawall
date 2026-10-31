#!/bin/bash
# Builds build/Seawall.app from the Swift package. No Xcode needed — Command Line Tools are enough.
#
#   scripts/build-app.sh            # release build, ad-hoc signed
#   SIGN_IDENTITY="Apple Development: …" scripts/build-app.sh
#   HARDENED_RUNTIME=1 SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
#
# HARDENED_RUNTIME=1 (what scripts/make-dmg.sh uses for a release) signs every piece with the
# hardened runtime and a secure timestamp, and the app with Resources/Seawall.entitlements, as
# notarization requires. It also refuses to build while SUPublicEDKey is the placeholder
# (REQUIRE_SPARKLE_KEY=1 does that alone). Without it, signing works as it always did.
#
# With ad-hoc signing macOS asks for Safari access again after every rebuild;
# a real signing identity keeps the permission.
#
# For trying out updates (docs/UPDATES.md), the copied Info.plist can be changed without
# editing Resources/Info.plist: APP_VERSION=0.1.0 APP_BUILD=1 FEED_URL=http://127.0.0.1:8000/appcast.xml
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
IDENTITY="${SIGN_IDENTITY:--}"
APP="build/Seawall.app"
ENTITLEMENTS="Resources/Seawall.entitlements"
HARDENED="${HARDENED_RUNTIME:-0}"

if [ "$HARDENED" = "1" ]; then
    if [ "$IDENTITY" = "-" ]; then
        echo "error: HARDENED_RUNTIME=1 needs a real SIGN_IDENTITY; ad-hoc signatures can't be timestamped or notarized." >&2
        exit 1
    fi
    if [ ! -f "$ENTITLEMENTS" ]; then
        echo "error: HARDENED_RUNTIME=1 needs $ENTITLEMENTS (the apple-events entitlement for reading browser tabs)." >&2
        exit 1
    fi
fi

# Sparkle won't start with the placeholder key, so such a build runs with updates off.
# Fine for local builds; a release must have the real key from generate_keys.
if grep -q "REPLACE_WITH_PUBLIC_KEY" Resources/Info.plist; then
    if [ "${REQUIRE_SPARKLE_KEY:-$HARDENED}" = "1" ]; then
        echo "error: SUPublicEDKey in Resources/Info.plist is still the placeholder. See docs/UPDATES.md." >&2
        exit 1
    fi
    echo "warning: SUPublicEDKey is still the placeholder, so this build has updates off. See docs/UPDATES.md." >&2
fi

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

# SwiftPM copies the framework from Sparkle's xcframework next to the binary; fall back to
# the downloaded artifact itself.
SPARKLE="$BIN_DIR/Sparkle.framework"
if [ ! -d "$SPARKLE" ]; then
    SPARKLE="$(find .build/artifacts -type d -path "*Sparkle.xcframework/macos-*/Sparkle.framework" -print -quit 2>/dev/null || true)"
fi
if [ -z "$SPARKLE" ] || [ ! -d "$SPARKLE" ]; then
    echo "error: Sparkle.framework not found under $BIN_DIR or .build/artifacts" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Seawall" "$APP/Contents/MacOS/Seawall"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# ditto keeps the framework's Versions/Current symlinks as symlinks.
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"

PLIST="$APP/Contents/Info.plist"
if [ -n "${APP_VERSION:-}" ]; then plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$PLIST"; fi
if [ -n "${APP_BUILD:-}" ]; then plutil -replace CFBundleVersion -string "$APP_BUILD" "$PLIST"; fi
if [ -n "${FEED_URL:-}" ]; then plutil -replace SUFeedURL -string "$FEED_URL" "$PLIST"; fi

# Signed inside out, each piece on its own, as Sparkle's docs ask: no --deep, which would
# drop the Downloader service's own entitlements. A release (HARDENED_RUNTIME=1) also gets the
# hardened runtime and a secure timestamp on every piece, which notarization needs.
SIGN=(codesign --force --sign "$IDENTITY")
if [ "$HARDENED" = "1" ]; then
    SIGN+=(--options runtime --timestamp)
fi
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
VERSIONED="$FRAMEWORK/Versions/B"
for item in "$VERSIONED/XPCServices/Installer.xpc" "$VERSIONED/Autoupdate" "$VERSIONED/Updater.app"; do
    if [ -e "$item" ]; then "${SIGN[@]}" "$item"; fi
done
if [ -e "$VERSIONED/XPCServices/Downloader.xpc" ]; then
    "${SIGN[@]}" --preserve-metadata=entitlements "$VERSIONED/XPCServices/Downloader.xpc"
fi
"${SIGN[@]}" "$FRAMEWORK"

# Under the hardened runtime, reading Safari and Chrome tabs needs the apple-events entitlement.
if [ "$HARDENED" = "1" ]; then
    "${SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP"
else
    "${SIGN[@]}" "$APP"
fi

echo "Built $APP"
