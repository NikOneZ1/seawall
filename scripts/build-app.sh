#!/bin/bash
# Builds build/Seawall.app from the Swift package. No Xcode needed — Command Line Tools are enough.
#
#   scripts/build-app.sh            # release build, ad-hoc signed
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
#
# With ad-hoc signing macOS asks for Safari access again after every rebuild;
# a real signing identity keeps the permission, and turns on the hardened runtime
# that notarization needs.
#
# Automatic updates are only switched on when SPARKLE_FEED_URL says where the appcast lives
# (scripts/release.sh sets it); otherwise the app never checks for updates. The public key
# updates are checked against is in Resources/Info.plist.
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
# ditto keeps the framework's symlinks, which codesign insists on.
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

PLIST="$APP/Contents/Info.plist"
# VERSION ("1.0.0") and BUILD (a number that only goes up; Sparkle compares it) stamp a release.
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
fi
if [[ -n "${BUILD:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
fi
if [[ -n "${SPARKLE_FEED_URL:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$PLIST"
    echo "Updates on, from $SPARKLE_FEED_URL"
fi

# Sparkle's helpers are signed one by one, inside out; --deep would sign them wrongly.
SIGN=(codesign --force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
    SIGN+=(--options runtime --timestamp)
fi
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
"${SIGN[@]}" "$SPARKLE/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPARKLE/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Updater.app"
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
# The entitlement lets the hardened runtime send Apple Events, which is how tabs are read.
"${SIGN[@]}" --entitlements Resources/Seawall.entitlements "$APP"

echo "Built $APP"
