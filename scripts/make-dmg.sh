#!/bin/bash
# Builds a Developer ID signed, notarized and stapled dist/Seawall-<version>.dmg
# (plus a dist/Seawall.dmg copy for the website's /download link). See docs/RELEASING.md.
#
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/make-dmg.sh
#
# Environment:
#   SIGN_IDENTITY   required; a "Developer ID Application: …" identity in the keychain
#   NOTARY_PROFILE  notarytool keychain profile (default: seawall-notary)
#   SKIP_NOTARIZE=1 sign only, no notarization or stapling (local dry run; not shippable)
set -euo pipefail

cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-seawall-notary}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
APP="build/Seawall.app"
DIST="dist"

die() { echo "make-dmg: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

# --- Identity -------------------------------------------------------------------------------

IDENTITY="${SIGN_IDENTITY:-}"
[ -n "$IDENTITY" ] || die 'SIGN_IDENTITY is not set. Use your "Developer ID Application: Name (TEAMID)" identity.
List yours with: security find-identity -v -p codesigning'
case "$IDENTITY" in
    -)
        die 'SIGN_IDENTITY="-" (ad-hoc) cannot be notarized. Use a "Developer ID Application: …" identity.' ;;
    "Apple Development:"*|"Mac Developer:"*|"Apple Distribution:"*|"3rd Party Mac Developer"*)
        die "\"$IDENTITY\" is not a Developer ID identity; only \"Developer ID Application: …\" can be notarized for distribution outside the App Store." ;;
    "Developer ID Application:"*) ;;
    *)
        die "SIGN_IDENTITY must start with \"Developer ID Application:\" (got \"$IDENTITY\")." ;;
esac

for tool in codesign hdiutil xcrun spctl ditto security plutil /usr/libexec/PlistBuddy; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool not found; this script runs on macOS with the Command Line Tools."
done

security find-identity -v -p codesigning | grep -qF "\"$IDENTITY\"" \
    || die "\"$IDENTITY\" is not a valid code signing identity in your keychain (security find-identity -v -p codesigning)."

# --- Version --------------------------------------------------------------------------------

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
[ -n "$VERSION" ] || die "could not read CFBundleShortVersionString from Resources/Info.plist"
DMG="$DIST/Seawall-$VERSION.dmg"
echo "Seawall $VERSION, signing as: $IDENTITY"

# --- Build and sign the app (bundle assembly lives in build-app.sh) -------------------------

step "Building $APP (release, hardened runtime)"
CONFIG=release HARDENED_RUNTIME=1 SIGN_IDENTITY="$IDENTITY" ./scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 "$APP"

# --- Disk image -----------------------------------------------------------------------------

step "Creating $DMG"
mkdir -p "$DIST"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/seawall-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Seawall.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG" "$DIST/Seawall.dmg"
hdiutil create -volname Seawall -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"

step "Signing $DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
codesign --verify --strict --verbose=2 "$DMG"

# --- Notarize and staple --------------------------------------------------------------------

if [ "$SKIP_NOTARIZE" = "1" ]; then
    echo
    echo "SKIP_NOTARIZE=1: skipping notarization and stapling. This DMG is NOT ready to publish;"
    echo "Gatekeeper will reject it on other Macs."
else
    step "Notarizing (profile: $NOTARY_PROFILE); this usually takes a few minutes"
    RESULT="$STAGING/notary.json"
    # notarytool can exit 0 with status "Invalid", so judge by the status field, not the exit code.
    if ! xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
            --output-format json >"$RESULT"; then
        cat "$RESULT" >&2 || true
        rm -f "$DMG"
        die "notarytool submit failed. Check the profile: xcrun notarytool history --keychain-profile \"$NOTARY_PROFILE\""
    fi
    SUBMISSION_ID="$(plutil -extract id raw -o - "$RESULT" 2>/dev/null || true)"
    STATUS="$(plutil -extract status raw -o - "$RESULT" 2>/dev/null || true)"
    echo "Submission ${SUBMISSION_ID:-?}: ${STATUS:-unknown}"
    if [ "$STATUS" != "Accepted" ]; then
        cat "$RESULT" >&2
        rm -f "$DMG"   # don't leave an unnotarized DMG in dist/ where it could get published
        die "notarization did not succeed (status: ${STATUS:-unknown}). See why with:
  xcrun notarytool log ${SUBMISSION_ID:-<submission-id>} --keychain-profile \"$NOTARY_PROFILE\""
    fi

    step "Stapling"
    xcrun stapler staple "$DMG"
fi

# --- Verify ---------------------------------------------------------------------------------

step "Verifying"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --verbose=2 "$APP" 2>&1 | grep -E '^(Authority|TeamIdentifier|Timestamp|Runtime Version)=' || true
codesign --display --entitlements - "$APP"
if [ "$SKIP_NOTARIZE" = "1" ]; then
    echo "(skipping spctl and stapler validate: the DMG isn't notarized)"
else
    spctl -a -t open --context context:primary-signature -v "$DMG"
    xcrun stapler validate "$DMG"
fi

# --- Fixed-name copy for https://github.com/NikOneZ1/seawall/releases/latest/download/Seawall.dmg

cp "$DMG" "$DIST/Seawall.dmg"

echo
echo "Done:"
echo "  $DMG"
echo "  $DIST/Seawall.dmg"
if [ "$SKIP_NOTARIZE" != "1" ]; then
    echo
    echo "Publish with:"
    echo "  gh release create v$VERSION $DMG $DIST/Seawall.dmg --title \"Seawall $VERSION\""
fi
