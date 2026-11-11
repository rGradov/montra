#!/usr/bin/env bash
#
# Screenshots the Analytics "by day" heat map with the day popup open, one PNG
# per day of the current month. Each launch opens the requested day through
# MONTRA_ANALYTICS_POPUP, pins the window to the top-left of the usable screen
# area (MONTRA_ANALYTICS_SHOT) and prints one ANALYTICS_SHOT_JSON line with the
# real cell and popup rects, so placement can be checked without guessing.
#
# Usage: Scripts/analytics-popup-shots.sh <outdir> [YYYY-MM]
#
# The optional month (MONTRA_ANALYTICS_MONTH) shoots a past month, which is how a
# day with six or more categories can be captured from real data.
#
# Output per day: day-<n>.png, day-<n>.json (telemetry), day-<n>.log (stdout),
# day-<n>.stderr, plus index.tsv with one review row per day.
#
set -euo pipefail

OUTDIR="${1:?usage: Scripts/analytics-popup-shots.sh <outdir>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/DerivedData-debug/Build/Products/Debug/Montra.app"
BIN="$APP/Contents/MacOS/Montra"

if [ ! -x "$BIN" ]; then
    echo "error: debug build not found at $BIN" >&2
    echo "build it with: xcodebuild -project Montra.xcodeproj -scheme Montra -configuration Debug \\" >&2
    echo "  -derivedDataPath build/DerivedData-debug OTHER_SWIFT_FLAGS=-disable-sandbox build" >&2
    exit 2
fi

# The pixel assertion needs Pillow. Prefer an explicit interpreter, then the
# project venv, then the DSH runtime; refuse to run without one, because a
# harness that only trusts the JSON can save a popup-less frame as a pass.
PIL_PY=""
for candidate in "${MONTRA_PIL_PYTHON:-}" python3 "$ROOT/mcp/.venv/bin/python" \
    "${HOME:-/Users/vladrudenua}/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3"; do
    [ -n "$candidate" ] || continue
    [ -x "$candidate" ] || command -v "$candidate" >/dev/null 2>&1 || continue
    if "$candidate" -c "import PIL" 2>/dev/null; then
        PIL_PY="$candidate"
        break
    fi
done
if [ -z "$PIL_PY" ]; then
    echo "error: Pillow is required to assert that every popup is actually drawn." >&2
    echo "point MONTRA_PIL_PYTHON at a python with Pillow installed." >&2
    exit 3
fi

MONTH="${2:-}"
mkdir -p "$OUTDIR"
OUTDIR="$(cd "$OUTDIR" && pwd)"
INDEX="$OUTDIR/index.tsv"

# Days in the captured month; the default is the month the app opens on.
DAYS_IN_MONTH="$(python3 - "$MONTH" <<'PY'
import datetime
import sys

raw = sys.argv[1].strip()
if raw:
    year, month = (int(part) for part in raw.split("-"))
    first = datetime.date(year, month, 1)
else:
    today = datetime.date.today()
    first = datetime.date(today.year, today.month, 1)
next_month = datetime.date(first.year + (first.month == 12), (first.month % 12) + 1, 1)
print((next_month - datetime.timedelta(days=1)).day)
PY
)"

MONTH_ENV=()
if [ -n "$MONTH" ]; then
    MONTH_ENV=(--env "MONTRA_ANALYTICS_MONTH=$MONTH")
fi

# The app is launched through LaunchServices: a GUI process started straight from
# a shell has no window-server connection and never shows a window.
stop_app() {
    pkill -f "$BIN" 2>/dev/null || true
    for _ in $(seq 1 40); do
        pgrep -f "$BIN" >/dev/null 2>&1 || return 0
        sleep 0.1
    done
    pkill -9 -f "$BIN" 2>/dev/null || true
    sleep 0.2
}

cleanup() {
    stop_app
}
trap cleanup EXIT

json_field() {
    # json_field <file> <python expression over `d`>
    python3 - "$1" "$2" <<'PY'
import builtins
import json
import sys

path, expression = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as handle:
    payload = json.load(handle)
d = payload
helpers = {name: getattr(builtins, name) for name in ("abs", "float", "int", "len", "max", "min", "round", "str")}
print(eval(expression, {"__builtins__": {}, "builtins": builtins}, {"d": d, **helpers}))
PY
}

# Fraction of the reported popup rect that is drawn in the popup's own surface
# colour (`AppColors.surfaceRaised` = 0x2B2A28 = 43,42,40 in dark appearance,
# which the page never uses). A popup that was closed mid-capture by an
# activation change reads 0.0 here instead of being written as a pass.
popup_surface_fraction() {
    "$PIL_PY" - "$1" "$2" <<'PY'
import json
import sys

from PIL import Image

png, telemetry = sys.argv[1], sys.argv[2]
with open(telemetry, encoding="utf-8") as handle:
    d = json.load(handle)
popup = d["popup"]
scale = d["scale"]
surface = (43, 42, 40)
im = Image.open(png).convert("RGB")
x0 = max(0, int(popup["x"] * scale) + 3)
y0 = max(0, int(popup["y"] * scale) + 3)
x1 = min(im.width, int((popup["x"] + popup["w"]) * scale) - 3)
y1 = min(im.height, int((popup["y"] + popup["h"]) * scale) - 3)
matched = total = 0
for y in range(y0, y1, 3):
    for x in range(x0, x1, 3):
        total += 1
        matched += im.getpixel((x, y)) == surface
print(f"{matched / max(1, total):.3f}")
PY
}

printf 'day\tpopup\tside\tpopup_height\tcovers_cell\tinside_window\tcaret_ok\tgroups\trows\tpopup_pixels\tpng_bytes\tregion\n' > "$INDEX"

failures=0
popup_days=0

for day in $(seq 1 "$DAYS_IN_MONTH"); do
    log="$OUTDIR/day-$day.log"
    errlog="$OUTDIR/day-$day.stderr"
    json="$OUTDIR/day-$day.json"
    png="$OUTDIR/day-$day.png"
    rm -f "$log" "$errlog" "$json" "$png"

    stop_app

    open -n -a "$APP" \
        --env MONTRA_ANALYTICS_SCOPE=month \
        --env "MONTRA_ANALYTICS_POPUP=$day" \
        --env MONTRA_ANALYTICS_SHOT=1 \
        ${MONTH_ENV[@]+"${MONTH_ENV[@]}"} \
        --stdout "$log" \
        --stderr "$errlog"

    reported=0
    for _ in $(seq 1 80); do
        if [ -s "$log" ] && grep -q 'ANALYTICS_SHOT_JSON' "$log" 2>/dev/null; then
            reported=1
            break
        fi
        sleep 0.25
    done

    if [ "$reported" -ne 1 ]; then
        echo "FAIL day $day: no ANALYTICS_SHOT_JSON within 20s" >&2
        tail -n 20 "$log" >&2 2>/dev/null || true
        tail -n 20 "$errlog" >&2 2>/dev/null || true
        failures=$((failures + 1))
        continue
    fi

    # Keep the last telemetry line: the first one may come from an early layout.
    grep 'ANALYTICS_SHOT_JSON' "$log" | tail -n 1 \
        | sed 's/^.*ANALYTICS_SHOT_JSON //' > "$json"

    reported_day="$(json_field "$json" 'd["day"]')"
    if [ "$reported_day" != "$day" ]; then
        echo "FAIL day $day: telemetry reports day $reported_day" >&2
        failures=$((failures + 1))
        continue
    fi

    # Let the card settle after the popup report before the capture.
    sleep 0.5

    region="$(json_field "$json" \
        'f"{d["window"]["x"]:.0f},{d["window"]["y"]:.0f},{d["window"]["w"]:.0f},{d["window"]["h"]:.0f}"')"

    # A sleeping display makes `screencapture` fail with "could not create image
    # from rect", so wake it and retry instead of losing the day.
    captured=0
    for attempt in 1 2 3; do
        caffeinate -u -t 1 2>/dev/null || true
        if screencapture -x -R "$region" "$png" 2>/dev/null && [ -s "$png" ]; then
            captured=1
            break
        fi
        sleep 0.6
    done

    if [ "$captured" -ne 1 ]; then
        echo "FAIL day $day: screencapture failed three times for region $region" >&2
        failures=$((failures + 1))
        printf '%s\tcapture failed\t-\t-\t-\t-\t-\t-\t-\t-\t0\t%s\n' "$day" "$region" >> "$INDEX"
        continue
    fi

    bytes="$(stat -f%z "$png")"
    if [ "$bytes" -lt 60000 ]; then
        echo "FAIL day $day: PNG is only $bytes bytes; the calendar is probably not visible" >&2
        failures=$((failures + 1))
        continue
    fi

    # Cross-check the image against the telemetry: same pixel size as the window.
    scale="$(json_field "$json" 'd["scale"]')"
    expected_w="$(json_field "$json" 'round(d["window"]["w"] * d["scale"])')"
    expected_h="$(json_field "$json" 'round(d["window"]["h"] * d["scale"])')"
    actual_w="$(sips -g pixelWidth "$png" | awk '/pixelWidth/ {print $2}')"
    actual_h="$(sips -g pixelHeight "$png" | awk '/pixelHeight/ {print $2}')"
    if [ "$actual_w" != "$expected_w" ] || [ "$actual_h" != "$expected_h" ]; then
        echo "FAIL day $day: PNG is ${actual_w}x${actual_h}, expected ${expected_w}x${expected_h}" >&2
        failures=$((failures + 1))
        continue
    fi

    has_popup="$(json_field "$json" 'd["popup"] is not None')"
    if [ "$has_popup" = "True" ]; then
        popup_days=$((popup_days + 1))
        side="$(json_field "$json" 'd["side"]')"
        height="$(json_field "$json" 'f"{d["popupHeight"]:.1f}"')"
        covers="$(json_field "$json" 'd["coversCell"]')"
        inside="$(json_field "$json" \
            'd["popup"]["x"] >= 0 and d["popup"]["y"] >= 0 and d["popup"]["x"] + d["popup"]["w"] <= d["window"]["w"] and d["popup"]["y"] + d["popup"]["h"] <= d["window"]["h"]')"
        caret_ok="$(json_field "$json" \
            'abs(d["caretX"] - (d["cell"]["x"] + d["cell"]["w"] / 2)) <= 8')"
        groups="$(json_field "$json" 'd["groupCount"]')"
        rows="$(json_field "$json" 'd["visibleRowCount"]')"

        # The JSON alone is not proof: require the card's pixels in the frame.
        fraction="$(popup_surface_fraction "$png" "$json")"
        if ! awk -v value="$fraction" 'BEGIN { exit !(value >= 0.6) }'; then
            echo "FAIL day $day: telemetry reports a popup at $region but only $fraction of the card is drawn; the frame has no popup (activation change or a missing overlay)" >&2
            failures=$((failures + 1))
            printf '%s\tpopup missing\t-\t-\t-\t-\t-\t%s\t%s\t%s\t%s\t%s\n' \
                "$day" "$groups" "$rows" "$fraction" "$bytes" "$region" >> "$INDEX"
            continue
        fi

        if [ "$covers" = "True" ]; then
            echo "FAIL day $day: the popup covers the clicked cell" >&2
            failures=$((failures + 1))
        fi
        if [ "$inside" != "True" ]; then
            echo "FAIL day $day: the popup is not fully inside the window" >&2
            failures=$((failures + 1))
        fi
        if [ "$caret_ok" != "True" ]; then
            echo "FAIL day $day: the caret does not point at the cell centre" >&2
            failures=$((failures + 1))
        fi
        printf '%s\tyes\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$day" "$side" "$height" "$covers" "$inside" "$caret_ok" "$groups" "$rows" "$fraction" "$bytes" "$region" \
            >> "$INDEX"
        echo "day $day: popup=yes side=$side height=$height groups=$groups coversCell=$covers pixels=$fraction -> $png"
    else
        reason="$(json_field "$json" 'd.get("reason", "unknown")')"
        printf '%s\tno (%s)\t-\t-\t-\t-\t-\t-\t-\t-\t%s\t%s\n' \
            "$day" "$reason" "$bytes" "$region" >> "$INDEX"
        echo "day $day: popup=no reason=$reason -> $png"
    fi
done

stop_app

echo
echo "shots: $OUTDIR${MONTH:+ (month $MONTH)}"
echo "days with a popup: $popup_days of $DAYS_IN_MONTH"
echo "index: $INDEX"

if [ "$failures" -ne 0 ]; then
    echo "FAILED: $failures check(s) failed" >&2
    exit 1
fi
echo "OK: every day captured and every popup passed the placement checks"
