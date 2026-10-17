#!/bin/zsh
# Captures real Hyena screens using demo mode (sample data, never touches your files).
# Needs an unlocked screen and Screen Recording permission for your terminal.
# Output: docs/screens/<name>.png (Retina, rounded corners, transparent background).
set -euo pipefail
cd "${0:A:h:h}"
OUT="$PWD/docs/screens"
APP="$PWD/dist/Hyena.app"
TMP="$(mktemp -d)"
mkdir -p "$OUT"
zsh scripts/build-app.sh >/dev/null
swiftc -O scripts/tools/window-rect.swift -o "$TMP/window-rect"
swiftc -O scripts/tools/park-cursor.swift -o "$TMP/park-cursor"

screens=(${@:-overview tree ask explain clean downloads simulators})
for screen in $screens; do
  pkill -x Hyena 2>/dev/null || true
  sleep 1
  open -n "$APP" --args --demo "--demo-screen=$screen"
  sleep 9
  rect="$("$TMP/window-rect")"
  [[ -n "$rect" ]] || { print "No Hyena window for $screen"; continue; }
  IFS=, read -r x y w h screenWidth <<< "$rect"
  osascript -e 'tell application "System Events" to set frontmost of (first process whose name is "Hyena") to true'
  "$TMP/park-cursor"
  sleep 1.5
  screencapture -x "$TMP/full.png"
  scale=$(( $(magick identify -format "%w" "$TMP/full.png") / screenWidth ))
  radius=$(( 16 * scale ))
  magick "$TMP/full.png" -crop "$((w*scale))x$((h*scale))+$((x*scale))+$((y*scale))" +repage \
    \( +clone -alpha extract -fill black -colorize 100 -fill white \
       -draw "roundrectangle 0,0,$((w*scale-1)),$((h*scale-1)),$radius,$radius" \) \
    -alpha off -compose CopyOpacity -composite "$OUT/$screen.png"
  print "Captured $screen"
done
pkill -x Hyena 2>/dev/null || true
rm -rf "$TMP"
