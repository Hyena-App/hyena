#!/bin/zsh
# Builds a release DMG: VERSION=0.2.0 [BUILD_NUMBER=7] zsh scripts/release.sh
# Signs with a "Developer ID Application" identity when one is in the keychain
# (hardened runtime + entitlements), otherwise ad-hoc. Notarizes and staples when
# NOTARY_KEY_PATH, NOTARY_KEY_ID and NOTARY_ISSUER are set.
# Writes `dmg` and `sha256` to $GITHUB_OUTPUT when running in Actions.
set -euo pipefail
cd "${0:A:h:h}"
: "${VERSION:?Set VERSION, e.g. VERSION=0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP="$PWD/dist/Hyena.app"
DMG="$PWD/dist/Hyena-$VERSION.dmg"

zsh scripts/build-app.sh
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD_NUMBER" \
  "$APP/Contents/Info.plist"

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Developer ID Application' | sed -E 's/.*"(.*)"/\1/' || true)"
if [[ -n "$IDENTITY" ]]; then
  print "Signing with: $IDENTITY"
  codesign --force --options runtime --timestamp --entitlements Resources/Hyena.entitlements --sign "$IDENTITY" "$APP"
else
  print "No Developer ID identity found; ad-hoc signing."
  codesign --force --entitlements Resources/Hyena.entitlements --sign - "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Hyena" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
[[ -n "$IDENTITY" ]] && codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" && -n "$IDENTITY" ]]; then
  xcrun notarytool submit "$DMG" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
  xcrun stapler staple "$DMG"
else
  print "Notarization skipped (needs a Developer ID identity and App Store Connect API key)."
fi

SHA256="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
print "Built $DMG ($SHA256)"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  print "dmg=$DMG" >> "$GITHUB_OUTPUT"
  print "sha256=$SHA256" >> "$GITHUB_OUTPUT"
fi
