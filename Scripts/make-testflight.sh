#!/bin/bash
# Build an App Store / TestFlight archive and export an IPA for Transporter.
#
# Preconditions (one-time, in Xcode / Apple Developer):
#   1. Xcode → Settings → Accounts: add the Apple ID that belongs to team
#      97S3QGCCV4 and let Xcode manage signing.
#   2. developer.apple.com → Identifiers → app.finance.montra: enable iOS and
#      iCloud/CloudKit with container iCloud.app.finance.montra (Push off).
#      Xcode automatic signing can usually do this for an admin account.
#   3. App Store Connect: one universal app record for app.finance.montra.
#
# Usage:
#   Scripts/make-testflight.sh
#   BUILD_NUMBER=2 Scripts/make-testflight.sh
#
# It writes build/TestFlight/Montra.ipa; upload it with Transporter. Build
# numbers must increase for every upload.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
team="${TEAM_ID:-97S3QGCCV4}"
bundle="app.finance.montra"
build="${BUILD_NUMBER:-1}"
project="$root/Montra.xcodeproj"
out="$root/build/TestFlight"
archive="$out/Montra.xcarchive"
ipa_dir="$out/ipa"
log="$out/archive.log"

mkdir -p "$out"
rm -rf "$archive" "$ipa_dir"

echo "==> Preflight"
if ! security find-identity -v -p codesigning | grep -q "Apple Distribution"; then
    echo "NOTE: no Apple Distribution certificate in the keychain."
    echo "      Sign in to Xcode → Settings → Accounts; Xcode can create one."
fi
if [[ ! -d "$HOME/Library/Developer/Xcode/UserData/Accounts" ]]; then
    echo "NOTE: Xcode has no signed-in account for this user."
    echo "      Add the Apple ID under Xcode → Settings → Accounts first."
fi

echo "==> Archiving (Release, generic iOS, build $build)"
set +e
xcodebuild \
    -project "$project" \
    -scheme Montra \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$team" \
    CODE_SIGN_STYLE=Automatic \
    CURRENT_PROJECT_VERSION="$build" \
    archive > "$log" 2>&1
status=$?
set -e

if [[ $status -ne 0 ]]; then
    echo "Archive failed. Relevant errors:" >&2
    grep -E "error:|No Accounts|No signing|iCloud|provisioning" "$log" | tail -20 >&2 || true
    cat <<EOF >&2

Next steps:
  • Xcode → Settings → Accounts → add the Apple ID for team $team.
  • Developer portal → Identifiers → $bundle → enable iOS and
    iCloud/CloudKit with container iCloud.app.finance.montra.
  • Developer portal → Certificates → create an Apple Distribution certificate
    (or let Xcode automatic signing create it).
  • App Store Connect → create the universal app record if it does not exist.
Then rerun: BUILD_NUMBER=$build Scripts/make-testflight.sh
Log: $log
EOF
    exit 1
fi

echo "==> Exporting IPA"
cat > "$out/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>$team</string>
    <key>uploadSymbols</key>
    <true/>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF

xcodebuild \
    -exportArchive \
    -archivePath "$archive" \
    -exportPath "$ipa_dir" \
    -exportOptionsPlist "$out/ExportOptions.plist" \
    -allowProvisioningUpdates > "$out/export.log" 2>&1 || {
    echo "Export failed:" >&2
    tail -20 "$out/export.log" >&2
    exit 1
}

ipa="$ipa_dir/Montra.ipa"
[[ -f "$ipa" ]] || { echo "No IPA produced; see $out/export.log" >&2; exit 1; }
size="$(du -h "$ipa" | cut -f1)"
echo
echo "IPA ready: $ipa ($size)"
echo "Build:     $(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$archive/Info.plist" 2>/dev/null || echo 1.0) ($build)"
echo "Upload:    open Transporter, choose this IPA, Deliver."
echo "Note:      increment BUILD_NUMBER for every upload."
