#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/Hyena.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Hyena" "$APP/Contents/MacOS/Hyena"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# The icon is rendered from the same vector artwork the app draws.
ICONSET="$(mktemp -d)/Hyena.iconset"
"$BIN_DIR/Hyena" --render-icon "$ICONSET"
rm -rf Resources/Hyena.iconset && cp -R "$ICONSET" Resources/Hyena.iconset
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Hyena.icns"
codesign --force --sign - "$APP"
print "Built $APP"
