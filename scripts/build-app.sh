#!/bin/bash
# Builds build/FocusLock.app from the Swift package. No Xcode needed — Command Line Tools are enough.
#
#   scripts/build-app.sh            # release build, ad-hoc signed
#   SIGN_IDENTITY="Apple Development: …" scripts/build-app.sh
#
# With ad-hoc signing macOS asks for Safari access again after every rebuild;
# a real signing identity keeps the permission.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
IDENTITY="${SIGN_IDENTITY:--}"
APP="build/FocusLock.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/FocusLock" "$APP/Contents/MacOS/FocusLock"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "$IDENTITY" "$APP"

echo "Built $APP"
