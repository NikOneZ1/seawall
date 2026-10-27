#!/bin/bash
# Makes a release in dist/: Seawall-<version>.dmg for the website, and for automatic updates
# Seawall-<version>.zip plus an appcast.xml listing it.
#
#   scripts/release.sh 1.0.0
#
# Settings, from the environment (each missing one skips its step and says so):
#   SIGN_IDENTITY        "Developer ID Application: Name (TEAMID)". Without it the build is
#                        ad-hoc signed, and Gatekeeper won't open a downloaded copy.
#   NOTARY_PROFILE       a notarytool keychain profile, made once with
#                        `xcrun notarytool store-credentials <name> --apple-id … --team-id …`
#   SPARKLE_FEED_URL     where appcast.xml will be served
#   SPARKLE_PUBLIC_KEY   the public key printed by Sparkle's generate_keys
#   DOWNLOAD_URL_PREFIX  where the zips will be served, e.g. https://example.com/updates/
#
# The build number is the number of commits on HEAD, so it only goes up.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:?Usage: scripts/release.sh <version>, e.g. 1.0.0}"
BUILD="$(git rev-list --count HEAD)"
APP="build/Seawall.app"
DIST="dist"
UPDATES="$DIST/updates"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"

skip() { echo "⚠︎ Skipping $1: $2 is not set."; }

if [[ -n "$(git status --porcelain)" ]]; then
    echo "⚠︎ The working tree has uncommitted changes; this release won't match a commit."
fi

VERSION="$VERSION" BUILD="$BUILD" ./scripts/build-app.sh
mkdir -p "$UPDATES"

if [[ -n "${NOTARY_PROFILE:-}" && -n "${SIGN_IDENTITY:-}" ]]; then
    ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"
    xcrun notarytool submit "$DIST/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    rm "$DIST/notarize.zip"
    xcrun stapler staple "$APP"
else
    skip "notarization" "NOTARY_PROFILE or SIGN_IDENTITY"
fi

# For Sparkle: a zip of the (stapled) app.
ZIP="$UPDATES/Seawall-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# For the website: a disk image with the app and a shortcut to Applications.
DMG="$DIST/Seawall-$VERSION.dmg"
STAGE="$(mktemp -d)"
ditto "$APP" "$STAGE/Seawall.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Seawall" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
    fi
fi

# The appcast is signed with the private key generate_keys keeps in the login keychain.
if [[ -n "${DOWNLOAD_URL_PREFIX:-}" && -n "${SPARKLE_FEED_URL:-}" ]]; then
    "$SPARKLE_BIN/generate_appcast" --download-url-prefix "$DOWNLOAD_URL_PREFIX" -o "$DIST/appcast.xml" "$UPDATES"
else
    skip "the appcast" "DOWNLOAD_URL_PREFIX or SPARKLE_FEED_URL"
fi

echo
echo "Seawall $VERSION ($BUILD):"
ls -lh "$DIST" "$UPDATES" | grep -v '^total'
