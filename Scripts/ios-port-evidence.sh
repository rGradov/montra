#!/bin/bash
# Capture the same screens on macOS, iPhone and iPad and compose comparison
# images. Run after the iOS/macOS builds; this script never builds anything.
#
# Usage: Scripts/ios-port-evidence.sh [output-folder]
#
# The macOS app renders its own snapshots (in-memory fixtures). The simulators
# are booted one at a time and shut down before the next device starts, so this
# stays light on a laptop.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-$root/Docs/screenshots/ios-port}"
mac_app="$root/build/DerivedData-final/Build/Products/Debug/Montra.app"
ios_app="$root/build/DerivedData-final-ios/Build/Products/Debug-iphonesimulator/Montra.app"
iphone="${IPHONE_UDID:-345F666D-401A-48DF-A69A-458497F56A39}"
ipad="${IPAD_UDID:-36CD47B2-B476-4F8B-9FBA-F5FC8D1D5C0F}"
bundle="app.finance.montra"
raw="$root/build/evidence-raw"
mac_snaps="$root/build/evidence-mac-snaps"

[[ -d "$mac_app" ]] || { echo "missing macOS app: $mac_app" >&2; exit 1; }
[[ -d "$ios_app" ]] || { echo "missing iOS app: $ios_app" >&2; exit 1; }

mkdir -p "$out" "$raw" "$mac_snaps"

# 1. macOS: render every screen once with the in-memory fixture store.
"$mac_app/Contents/MacOS/Montra" -snapshot "$mac_snaps" >/dev/null
for pair in \
  "overview:01-overview-dark.png" \
  "analytics:06-analytics-dark.png" \
  "settings:05-settings-dark.png" \
  "about:07-about-dark.png" \
  "new-operation:10-new-operation.png" \
  "onboarding:13-onboarding-welcome.png"; do
  name="${pair%%:*}"; file="${pair##*:}"
  cp "$mac_snaps/$file" "$raw/macos-$name.png"
done

# 2. iPhone and iPad, one device at a time.
capture_device() {
  local udid="$1" slug="$2"
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  sleep 8
  xcrun simctl uninstall "$udid" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$ios_app"
  xcrun simctl status_bar "$udid" override --time "9:41" \
    --batteryState charged --batteryLevel 100 --wifiBars 3 >/dev/null 2>&1 || true

  shot() {
    local name="$1"; shift
    xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
    xcrun simctl launch "$udid" "$bundle" "$@" >/dev/null
    sleep 5
    xcrun simctl io "$udid" screenshot "$raw/$slug-$name.png" >/dev/null 2>&1
    echo "  $slug $name"
  }

  shot overview -qa-demo -qa-route overview -qa-appearance dark
  shot analytics -qa-demo -qa-route analytics -qa-appearance dark
  shot settings -qa-demo -qa-route settings -qa-appearance dark
  shot about -qa-demo -qa-route settings -qa-sheet about -qa-appearance dark
  shot new-operation -qa-demo -qa-route overview -qa-sheet new-operation -qa-appearance dark

  xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl launch "$udid" "$bundle" -preview-onboarding -qa-appearance dark >/dev/null
  sleep 12
  xcrun simctl io "$udid" screenshot "$raw/$slug-onboarding.png" >/dev/null 2>&1
  echo "  $slug onboarding"

  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
}

capture_device "$iphone" "iphone"
capture_device "$ipad" "ipad"

# 3. Side-by-side comparison: macOS, iPhone, iPad at the same height.
python3 - "$raw" "$out" <<'PY'
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

raw, out = Path(sys.argv[1]), Path(sys.argv[2])
screens = ["overview", "analytics", "settings", "about", "new-operation", "onboarding"]
labels = ["macOS", "iPhone", "iPad"]
files = ["macos", "iphone", "ipad"]
height = 1000
pad = 24
label_h = 54
bg = (18, 17, 16)
ink = (236, 234, 230)

try:
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 30)
except Exception:
    font = ImageFont.load_default(size=30)

for screen in screens:
    panels = []
    for key in files:
        path = raw / f"{key}-{screen}.png"
        if not path.exists():
            print("missing", path)
            continue
        im = Image.open(path).convert("RGB")
        w = round(im.width * height / im.height)
        panels.append((key, im.resize((w, height), Image.LANCZOS)))
    if not panels:
        continue

    width = sum(im.width for _, im in panels) + pad * (len(panels) + 1)
    canvas = Image.new("RGB", (width, height + label_h + pad), bg)
    draw = ImageDraw.Draw(canvas)
    x = pad
    for index, (key, im) in enumerate(panels):
        canvas.paste(im, (x, label_h))
        label = labels[files.index(key)]
        draw.text((x + 12, 12), label, font=font, fill=ink)
        x += im.width + pad
    target = out / f"compare-{screen}.png"
    canvas.save(target)
    print("wrote", target)
PY

echo "done: $out"
