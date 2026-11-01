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

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

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

# The dev license (SEAWALL_DEV_LICENSE, see DevLicense) is compiled into debug builds only.
# A release build that still names it fails here instead of shipping.
if [[ "$CONFIG" == "release" ]] && strings -a "$APP/Contents/MacOS/Seawall" | grep -q SEAWALL_DEV_LICENSE; then
    echo "error: this release build contains the debug-only dev license" >&2
    exit 1
fi

echo "Built $APP"
