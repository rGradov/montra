#!/bin/bash
# Build Montra, prove the money rules still pass, and wrap the app in a DMG
# the person can install by dragging it to Applications.
#
# Usage:
#   Scripts/make-dmg.sh <tag> [--open]
#
# Example:
#   Scripts/make-dmg.sh hidden-accounts
#   -> build/Montra-1.0-hidden-accounts.dmg
#
# The tag is a short kebab-case description of the feature being tried.
# The script refuses to package anything when -selftest fails.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tag=""
open_after=0
for argument in "$@"; do
    case "$argument" in
        --open) open_after=1 ;;
        -*) echo "unknown option: $argument" >&2; exit 64 ;;
        *) tag="$argument" ;;
    esac
done

if [[ -z "$tag" ]]; then
    echo "usage: Scripts/make-dmg.sh <tag> [--open]" >&2
    echo "example: Scripts/make-dmg.sh hidden-accounts" >&2
    exit 64
fi
if [[ ! "$tag" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
    echo "tag must be kebab-case: lowercase letters, digits, dots, dashes" >&2
    exit 64
fi

project="$root/Montra.xcodeproj"
# A concurrent agent/build may hold the default DerivedData lock; allow an
# isolated path without changing the normal workflow.
derived="${MONTRA_DERIVED_DATA:-$root/build/DerivedData-release}"
app="$derived/Build/Products/Release/Montra.app"
staging="${MONTRA_DMG_STAGING:-$root/build/dmg-staging-$tag}"
version="$(grep -m1 'MARKETING_VERSION = ' "$project/project.pbxproj" | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/' | tr -d ' ')"
version="${version:-1.0}"
dmg="$root/build/Montra-$version-$tag.dmg"

# Apple's macro plugin server nests sandbox-exec, which the DSH workspace
# sandbox blocks. SwiftData's macro is Apple's own; disabling its extra sandbox
# keeps the build usable from the agent. Set MONTRA_DISABLE_MACRO_SANDBOX=0 in a
# normal terminal to keep the compiler's default isolation.
build_flags=()
if [[ "${MONTRA_DISABLE_MACRO_SANDBOX:-1}" == "1" ]]; then
    build_flags+=("OTHER_SWIFT_FLAGS=-disable-sandbox")
fi

echo "==> Building Release ($version)"
xcodebuild \
    -project "$project" \
    -scheme Montra \
    -configuration Release \
    -derivedDataPath "$derived" \
    "${build_flags[@]}" \
    build

[[ -d "$app" ]] || { echo "build finished without $app" >&2; exit 1; }

echo "==> Running the money and period self-test"
"$app/Contents/MacOS/Montra" -selftest

echo "==> Verifying the signature"
codesign --verify --deep --strict "$app"

echo "==> Staging"
case "$staging" in
    "$root"/build/dmg-staging*) ;;
    *) echo "refusing to clean an unexpected staging path: $staging" >&2; exit 1 ;;
esac
rm -rf -- "$staging"
mkdir -p "$staging"
cp -R "$app" "$staging/Montra.app"
ln -s /Applications "$staging/Applications"

echo "==> Creating $dmg"
hdiutil create -volname "Montra" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null

echo "==> Verifying the mounted image"
mount_point="$(mktemp -d "${TMPDIR:-/tmp}/montra-dmg.XXXXXX")"
cleanup() {
    # `mount` prints the resolved /private/var path while mktemp returns
    # /var/folders; detaching by the original mount point works either way.
    if [[ -n "${mount_point:-}" ]]; then
        hdiutil detach "$mount_point" >/dev/null 2>&1 || true
        rmdir "$mount_point" 2>/dev/null || true
    fi
}
trap cleanup EXIT

hdiutil attach -nobrowse -readonly -mountpoint "$mount_point" "$dmg" >/dev/null
[[ -d "$mount_point/Montra.app" ]] || { echo "the image has no Montra.app" >&2; exit 1; }
[[ -L "$mount_point/Applications" ]] || { echo "the image has no Applications link" >&2; exit 1; }
codesign --verify --deep --strict "$mount_point/Montra.app"
image_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$mount_point/Montra.app/Contents/Info.plist")"
image_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$mount_point/Montra.app/Contents/Info.plist")"
cleanup
trap - EXIT

size="$(du -h "$dmg" | cut -f1)"
echo
echo "DMG ready: $dmg"
echo "Version:   $image_version ($image_build), $size"
echo "Install:   open the image and drag Montra to Applications"

if [[ "$open_after" == "1" ]]; then
    open "$dmg"
fi
