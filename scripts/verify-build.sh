#!/bin/bash
# Checks that a built Seawall.app really is the build that just ran, and (for releases) that every
# binary in it runs on both Apple silicon and Intel.
#
#   scripts/verify-build.sh <path/to/Seawall.app> <build-start-epoch>
#   REQUIRE_ARCHS="arm64 x86_64" scripts/verify-build.sh build/Seawall.app "$BUILD_START"
#   REQUIRE_ARCHS="arm64 x86_64" scripts/verify-build.sh build/Seawall.app 0   # contents only
#
# Fails when:
#   - the app or Contents/MacOS/Seawall is missing;
#   - the executable is older than <build-start-epoch> (seconds since 1970, `date +%s`), i.e. a
#     leftover from an earlier build;
#   - REQUIRE_ARCHS is set and:
#       * the executable's architectures are not exactly REQUIRE_ARCHS (order doesn't matter);
#       * Sparkle.framework or one of its helpers (Autoupdate, Updater.app, Installer.xpc,
#         Downloader.xpc) is missing, or lacks one of REQUIRE_ARCHS;
#       * any other Mach-O file anywhere in the bundle lacks one of REQUIRE_ARCHS.
# Prebuilt parts (Sparkle) are only checked for architectures, not for age.
#
# Called by scripts/build-app.sh before signing and by scripts/release.sh right after the build.
# macOS only (needs lipo). Bash 3.2 compatible.
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <app> <build-start-epoch>" >&2
    exit 2
fi
APP="${1%/}"
START="$2"
REQUIRE_ARCHS="${REQUIRE_ARCHS:-}"

fail() {
    echo "error: build check failed for $APP: $*" >&2
    exit 1
}

case "$START" in
    ''|*[!0-9]*) fail "build start \"$START\" is not a number of seconds." ;;
esac

# Seconds-since-1970 modification time: GNU stat first, else BSD stat (macOS).
mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"
}

# Mach-O magic numbers (thin 32/64-bit either endianness, and fat/universal).
is_macho() {
    local magic
    # od may pad with spaces or tabs (BSD od on macOS); strip all whitespace and
    # lowercase so the magic-byte comparison is stable.
    magic=$(head -c 4 "$1" 2>/dev/null | od -An -tx1 | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    case "$magic" in
        feedface|cefaedfe|feedfacf|cffaedfe|cafebabe|bebafeca) return 0 ;;
    esac
    return 1
}

# Prints the sorted, space-separated architectures of a Mach-O file, or fails.
archs_of() {
    local out
    out=$(lipo -archs "$1" 2>/dev/null) || return 1
    [[ -n "$out" ]] || return 1
    printf '%s\n' $out | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# Fails unless the Mach-O $1 contains every architecture in REQUIRE_ARCHS.
require_archs() {
    local file="$1" have arch
    have=$(archs_of "$file") || fail "lipo can't read ${file#"$APP"/}."
    for arch in $REQUIRE_ARCHS; do
        case " $have " in
            *" $arch "*) ;;
            *) fail "${file#"$APP"/} has architectures \"$have\" but $arch is required." ;;
        esac
    done
}

command -v lipo >/dev/null 2>&1 || fail "lipo not found; this check runs on macOS."

[[ -d "$APP" ]] || fail "the app bundle does not exist."
EXE="$APP/Contents/MacOS/Seawall"
[[ -f "$EXE" ]] || fail "the executable $EXE is missing."
is_macho "$EXE" || fail "$EXE is not a Mach-O binary."

EXE_TIME=$(mtime "$EXE")
if (( EXE_TIME < START )); then
    fail "the executable is older than this build ($(date -r "$EXE_TIME" 2>/dev/null || echo "$EXE_TIME") < start $START); it is a leftover."
fi

if [[ -z "$REQUIRE_ARCHS" ]]; then
    echo "verified $EXE: fresh ($(archs_of "$EXE" || echo "unknown archs"); no architectures required)"
    exit 0
fi

# The main executable: exactly the required set, nothing missing and nothing extra.
WANT=$(printf '%s\n' $REQUIRE_ARCHS | sort -u | tr '\n' ' ' | sed 's/ $//')
HAVE=$(archs_of "$EXE") || fail "lipo can't read the executable."
[[ "$HAVE" == "$WANT" ]] || fail "the executable has architectures \"$HAVE\", expected exactly \"$WANT\"."

# Sparkle and its helpers, by name, so a missing helper fails loudly instead of being skipped.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in \
    "Sparkle" \
    "Autoupdate" \
    "Updater.app/Contents/MacOS/Updater" \
    "XPCServices/Installer.xpc/Contents/MacOS/Installer" \
    "XPCServices/Downloader.xpc/Contents/MacOS/Downloader"; do
    [[ -f "$SPARKLE/$part" ]] || fail "Sparkle part $part is missing from the bundle."
    require_archs "$SPARKLE/$part"
done

# Everything else: any Mach-O in the bundle (helpers, dylibs, XPC tools the app may grow later).
# find doesn't follow symlinks, so the framework's Versions/Current links aren't counted twice.
COUNT=0
while IFS= read -r -d '' file; do
    if is_macho "$file"; then
        require_archs "$file"
        COUNT=$((COUNT + 1))
    fi
done < <(find "$APP" -type f -print0)

echo "verified $EXE: fresh, $HAVE; all $COUNT Mach-O files in the bundle have $WANT"
