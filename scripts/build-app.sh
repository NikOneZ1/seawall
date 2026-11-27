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
# Release builds (CONFIG=release, the default) are universal: arm64 + x86_64, so the app runs on
# Intel Macs too. Debug builds (CONFIG=debug) are native-only unless UNIVERSAL=1.
#
#   CONFIG=debug scripts/build-app.sh             # native arch only, quickest
#   CONFIG=debug UNIVERSAL=1 scripts/build-app.sh # universal debug build
#
# Automatic updates are only switched on when SPARKLE_FEED_URL says where the appcast lives
# (scripts/release.sh sets it); otherwise the app never checks for updates. The public key
# updates are checked against is in Resources/Info.plist.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
IDENTITY="${SIGN_IDENTITY:--}"
APP="build/Seawall.app"

if [[ "$CONFIG" == "release" ]]; then
    UNIVERSAL=1
else
    UNIVERSAL="${UNIVERSAL:-0}"
fi
UNIVERSAL_ARCHS="arm64 x86_64"
SLICES="build/slices"
# Anything older than this is a leftover from an earlier build and must not end up in the app.
BUILD_START=$(date +%s)

# Seconds-since-1970 modification time: GNU stat first, else BSD stat (macOS).
mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"
}

# True when $1 exists, was written since BUILD_START, and lipo finds every arch in $2 in it.
fresh_product() {
    local file="$1" want="$2" have arch
    [[ -f "$file" ]] || return 1
    (( $(mtime "$file") >= BUILD_START )) || return 1
    have=" $(lipo -archs "$file" 2>/dev/null) " || return 1
    for arch in $want; do
        case "$have" in *" $arch "*) ;; *) return 1 ;; esac
    done
}

# True when the products dir $1 holds a Sparkle.framework whose binary has every arch in $2.
# Sparkle is a prebuilt (already universal) artifact, so it is checked for archs, not age, and
# never run through lipo.
sparkle_has() {
    local bin="$1/Sparkle.framework/Versions/B/Sparkle" have arch
    [[ -f "$bin" ]] || return 1
    have=" $(lipo -archs "$bin" 2>/dev/null) " || return 1
    for arch in $2; do
        case "$have" in *" $arch "*) ;; *) return 1 ;; esac
    done
}

# Removes a products dir SwiftPM reported, so the build that follows must write it fresh.
# Only ever inside .build/, and never .build itself (it holds the Sparkle checkout).
clear_products() {
    case "$1" in
        */.build|*/.build/|.build|.build/) echo "error: refusing to remove all of $1." >&2; exit 1 ;;
        */.build/?*|.build/?*) rm -rf "$1" ;;
        *) echo "error: SwiftPM reported products dir $1, outside .build/; not removing it." >&2; exit 1 ;;
    esac
}

if [[ "$UNIVERSAL" == "1" ]]; then
    echo "Universal build ($UNIVERSAL_ARCHS), $CONFIG"
    case "$CONFIG" in release) PRODUCTS_CONFIG=Release ;; debug) PRODUCTS_CONFIG=Debug ;; *) PRODUCTS_CONFIG="$CONFIG" ;; esac
    # Stale per-arch and per-platform products could otherwise be picked up (CineNotch 1.0.0 shipped
    # old slices from .build/<arch>-apple-macosx). The package checkouts in .build stay.
    rm -rf .build/arm64-apple-macosx .build/x86_64-apple-macosx \
        .build/arm64-apple-macosx14.0 .build/x86_64-apple-macosx14.0 \
        ".build/apple/Products/$PRODUCTS_CONFIG" ".build/out/Products/$PRODUCTS_CONFIG"
    rm -rf "${SLICES:?}"

    EXE_SRC=""
    BIN_DIR=""
    # 1) One SwiftPM invocation for both archs (needs a build system that supports several --arch,
    #    e.g. Xcode's; Command Line Tools alone usually refuse it, which is fine: see 2).
    ARGS=(-c "$CONFIG" --arch arm64 --arch x86_64)
    if SHOWN="$(swift build "${ARGS[@]}" --show-bin-path 2>/dev/null)" && [[ -n "$SHOWN" ]]; then
        clear_products "$SHOWN"
        if swift build "${ARGS[@]}"; then
            SHOWN_AFTER="$(swift build "${ARGS[@]}" --show-bin-path)"
            if [[ "$SHOWN_AFTER" == "$SHOWN" ]] && fresh_product "$SHOWN/Seawall" "$UNIVERSAL_ARCHS" \
                && sparkle_has "$SHOWN" "$UNIVERSAL_ARCHS"; then
                # Copy out right away so nothing later can overwrite what was checked.
                mkdir -p "$SLICES/universal"
                cp -p "$SHOWN/Seawall" "$SLICES/universal/Seawall"
                ditto "$SHOWN/Sparkle.framework" "$SLICES/universal/Sparkle.framework"
                EXE_SRC="$SLICES/universal/Seawall"
                BIN_DIR="$SLICES/universal"
                echo "Universal: one SwiftPM build, products from $SHOWN"
            else
                echo "⚠︎ The dual-arch SwiftPM build gave no fresh universal Seawall + Sparkle in $SHOWN; building each arch instead."
            fi
        else
            echo "⚠︎ SwiftPM can't build both archs in one go here; building each arch instead."
        fi
    else
        echo "⚠︎ SwiftPM can't resolve a dual-arch products dir here; building each arch instead."
    fi

    # 2) One build per arch. Each arch's products are copied into build/slices/<arch>/ straight
    #    after its own build: newer SwiftPM can report the same products dir for every triple, so
    #    the next build would overwrite them. Then lipo merges the staged copies only.
    if [[ -z "$EXE_SRC" ]]; then
        rm -rf "${SLICES:?}"
        LIPO_INPUTS=()
        for arch in $UNIVERSAL_ARCHS; do
            ARGS=(-c "$CONFIG" --triple "$arch-apple-macosx14.0")
            SHOWN="$(swift build "${ARGS[@]}" --show-bin-path)"
            clear_products "$SHOWN"
            swift build "${ARGS[@]}"
            SHOWN_AFTER="$(swift build "${ARGS[@]}" --show-bin-path)"
            if [[ "$SHOWN_AFTER" != "$SHOWN" ]]; then
                echo "error: SwiftPM's products dir for $arch moved during the build ($SHOWN -> $SHOWN_AFTER)." >&2
                exit 1
            fi
            if ! fresh_product "$SHOWN/Seawall" "$arch"; then
                echo "error: no fresh $arch Seawall in $SHOWN (built since $(date -r "$BUILD_START" 2>/dev/null || echo "epoch $BUILD_START")). Not using old binaries." >&2
                exit 1
            fi
            if ! sparkle_has "$SHOWN" "$UNIVERSAL_ARCHS"; then
                echo "error: $SHOWN/Sparkle.framework is missing or lacks one of $UNIVERSAL_ARCHS; not shipping a thinner updater." >&2
                exit 1
            fi
            mkdir -p "$SLICES/$arch"
            cp -p "$SHOWN/Seawall" "$SLICES/$arch/Seawall"
            ditto "$SHOWN/Sparkle.framework" "$SLICES/$arch/Sparkle.framework"
            LIPO_INPUTS+=("$SLICES/$arch/Seawall")
            echo "$arch: products from $SHOWN, staged in $SLICES/$arch"
        done
        mkdir -p "$SLICES/universal"
        lipo -create "${LIPO_INPUTS[@]}" -output "$SLICES/universal/Seawall"
        EXE_SRC="$SLICES/universal/Seawall"
        # Sparkle is the same prebuilt universal framework in every slice; take the first arch's.
        BIN_DIR="$SLICES/${UNIVERSAL_ARCHS%% *}"
    fi
else
    swift build -c "$CONFIG"
    BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
    EXE_SRC="$BIN_DIR/Seawall"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
# -p keeps the build's mtime, so the freshness check below sees when it was really built.
cp -p "$EXE_SRC" "$APP/Contents/MacOS/Seawall"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The blocked page embeds Barlow; its license travels with the app.
cp Resources/Fonts/Barlow-OFL.txt "$APP/Contents/Resources/Barlow-OFL.txt"
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

# Before signing: the executable is from this build, and (universal) every Mach-O in the bundle,
# Sparkle's helpers included, has both archs.
if [[ "$UNIVERSAL" == "1" ]]; then
    REQUIRE_ARCHS="$UNIVERSAL_ARCHS" ./scripts/verify-build.sh "$APP" "$BUILD_START"
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
# grep -a reads the raw bytes of every slice of a universal binary, with no pipe for pipefail to
# turn a match into a failure (strings | grep -q can die of SIGPIPE and hide the hit).
if [[ "$CONFIG" == "release" ]] && LC_ALL=C grep -a -q SEAWALL_DEV_LICENSE "$APP/Contents/MacOS/Seawall"; then
    echo "error: this release build contains the debug-only dev license" >&2
    exit 1
fi
# Same for the debug-only screenshot renderers (LicenseShots, DesignShots).
if [[ "$CONFIG" == "release" ]] && LC_ALL=C grep -a -q -E 'render-(license|design)-shots' "$APP/Contents/MacOS/Seawall"; then
    echo "error: this release build contains a debug-only screenshot renderer" >&2
    exit 1
fi

echo "Built $APP"
