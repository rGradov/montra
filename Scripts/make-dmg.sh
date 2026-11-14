#!/bin/bash
# Build Montra, prove the money rules still pass, and wrap the app in a DMG
# the person can install by dragging it to Applications.
#
# Usage:
#   Scripts/make-dmg.sh <tag> [--open] [--distribute]
#
# For a local QA image without a Developer ID provisioning profile, set
# MONTRA_LOCAL_SIGN=1: the app is built unsigned and ad-hoc signed before the
# image is created. The default path keeps the normal signing behaviour.
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
distribute=0
for argument in "$@"; do
    case "$argument" in
        --open) open_after=1 ;;
        --distribute) distribute=1 ;;
        -*) echo "unknown option: $argument" >&2; exit 64 ;;
        *) tag="$argument" ;;
    esac
done

if [[ -z "$tag" ]]; then
    echo "usage: Scripts/make-dmg.sh <tag> [--open] [--distribute]" >&2
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
staging="${MONTRA_DMG_STAGING:-$root/build/dmg-staging-$tag}"
version="$(grep -m1 'MARKETING_VERSION = ' "$project/project.pbxproj" | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/' | tr -d ' ')"
version="${version:-1.0}"
dmg="$root/build/Montra-$version-$tag.dmg"
image="$dmg"
distribution_dir=""
mount_point=""

detach_image() {
    if [[ -n "$mount_point" ]]; then
        hdiutil detach "$mount_point" >/dev/null
        rmdir "$mount_point"
        mount_point=""
    fi
}

cleanup() {
    detach_image 2>/dev/null || true
    if [[ -n "$distribution_dir" ]]; then
        rm -rf -- "$distribution_dir"
    fi
}
trap cleanup EXIT

# Apple's macro plugin server nests sandbox-exec, which the DSH workspace
# sandbox blocks. SwiftData's macro is Apple's own; disabling its extra sandbox
# keeps the build usable from the agent. Set MONTRA_DISABLE_MACRO_SANDBOX=0 in a
# normal terminal to keep the compiler's default isolation.
build_flags=()
if [[ "${MONTRA_DISABLE_MACRO_SANDBOX:-1}" == "1" ]]; then
    build_flags+=("OTHER_SWIFT_FLAGS=-disable-sandbox")
fi

local_sign="${MONTRA_LOCAL_SIGN:-0}"
if [[ "$local_sign" == "1" ]]; then
    build_flags+=("CODE_SIGNING_ALLOWED=NO")
fi

if [[ "$distribute" == "1" ]]; then
    notary_profile="${MONTRA_NOTARY_PROFILE:-montra-notary}"
    identities="$(security find-identity -v -p codesigning)"
    if [[ "$identities" != *'"Developer ID Application: '* ]]; then
        echo "No Developer ID Application signing identity in Keychain. See Docs/Feature-Workflow.md." >&2
        exit 1
    fi
    echo "==> Checking notarization credentials"
    xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null

    # Publish only a verified image. Keep intermediate files and the local
    # development build separate from the distribution build.
    mkdir -p "$root/build"
    distribution_dir="$(mktemp -d "$root/build/dmg-distribution.XXXXXX")"
    derived="$distribution_dir/DerivedData"
    staging="$distribution_dir/staging"
    dmg="${dmg%.dmg}-notarized.dmg"
    image="$distribution_dir/${dmg##*/}"
    build_flags+=(
        "CODE_SIGN_STYLE=Manual"
        "CODE_SIGN_IDENTITY=Developer ID Application"
        "CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO"
        "OTHER_CODE_SIGN_FLAGS=--timestamp"
    )
fi
app="$derived/Build/Products/Release/Montra.app"

echo "==> Building Release ($version)"
xcodebuild \
    -project "$project" \
    -scheme Montra \
    -configuration Release \
    -derivedDataPath "$derived" \
    "${build_flags[@]}" \
    build

[[ -d "$app" ]] || { echo "build finished without $app" >&2; exit 1; }

if [[ "$local_sign" == "1" ]]; then
    # Ad-hoc signature: valid locally, but not notarized and not for distribution.
    codesign --force --deep --sign - "$app" >/dev/null
fi

echo "==> Running the money and period self-test"
"$app/Contents/MacOS/Montra" -selftest

echo "==> Verifying the signature"
codesign --verify --deep --strict "$app"

echo "==> Staging"
case "$staging" in
    "$root"/build/dmg-staging*) ;;
    "$distribution_dir/staging") [[ -n "$distribution_dir" ]] || exit 1 ;;
    *) echo "refusing to clean an unexpected staging path: $staging" >&2; exit 1 ;;
esac
rm -rf -- "$staging"
mkdir -p "$staging"
cp -R "$app" "$staging/Montra.app"
ln -s /Applications "$staging/Applications"

echo "==> Creating ${image##*/}"
hdiutil create -volname "Montra" -srcfolder "$staging" -ov -format UDZO "$image" >/dev/null

echo "==> Verifying the mounted image"
mount_point="$(mktemp -d "${TMPDIR:-/tmp}/montra-dmg.XXXXXX")"
hdiutil attach -nobrowse -readonly -mountpoint "$mount_point" "$image" >/dev/null
[[ -d "$mount_point/Montra.app" ]] || { echo "the image has no Montra.app" >&2; exit 1; }
[[ -L "$mount_point/Applications" ]] || { echo "the image has no Applications link" >&2; exit 1; }
codesign --verify --deep --strict "$mount_point/Montra.app"
image_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$mount_point/Montra.app/Contents/Info.plist")"
image_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$mount_point/Montra.app/Contents/Info.plist")"
detach_image

local_sign="${MONTRA_LOCAL_SIGN:-0}"
if [[ "$local_sign" == "1" ]]; then
    build_flags+=("CODE_SIGNING_ALLOWED=NO")
fi

if [[ "$distribute" == "1" ]]; then
    echo "==> Signing the disk image with the app's Developer ID"
    codesign --verify -R='anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$app"
    codesign -d --extract-certificates="$distribution_dir/signing-cert-" "$app"
    identity="$(shasum -a 1 "$distribution_dir/signing-cert-0" | cut -d ' ' -f 1 | tr 'a-f' 'A-F')"
    codesign --sign "$identity" --timestamp "$image"

    echo "==> Submitting to Apple's notary service"
    submission="$distribution_dir/notary-result.json"
    if ! xcrun notarytool submit "$image" --keychain-profile "$notary_profile" \
        --wait --timeout 45m --output-format json > "$submission"; then
        cat "$submission" >&2
        exit 1
    fi
    cat "$submission"
    status="$(/usr/bin/plutil -extract status raw -o - "$submission")"
    if [[ "$status" != "Accepted" ]]; then
        submission_id="$(/usr/bin/plutil -extract id raw -o - "$submission")"
        if [[ "$status" == "Invalid" || "$status" == "Rejected" ]]; then
            xcrun notarytool log "$submission_id" --keychain-profile "$notary_profile" >&2
        fi
        echo "Notarization ended with status '$status' (submission: $submission_id)." >&2
        exit 1
    fi

    echo "==> Stapling the ticket and checking Gatekeeper"
    xcrun stapler staple "$image"
    xcrun stapler validate "$image"
    spctl --assess --type open --context context:primary-signature --verbose "$image"
    mv -f -- "$image" "$dmg"
fi

size="$(du -h "$dmg" | cut -f1)"
echo
echo "DMG ready: $dmg"
echo "Version:   $image_version ($image_build), $size"
echo "Install:   open the image and drag Montra to Applications"

if [[ "$open_after" == "1" ]]; then
    open "$dmg"
fi
