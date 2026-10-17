#!/bin/zsh
# Uploads the Developer ID certificate and notarization key to this repo's
# GitHub Actions secrets, so tagged releases are signed and notarized.
# Run it yourself: values are typed or read from files and piped straight to
# `gh secret set`. Nothing is printed, logged or committed.
#
# You need:
#   1. Your "Developer ID Application" certificate exported as .p12
#      (Keychain Access → My Certificates → right-click it → Export…).
#   2. The App Store Connect API key (.p8) you use for notarization, with its
#      Key ID and Issuer ID (App Store Connect → Users and Access → Integrations).
#      The same key used for other apps on your team works here too.
set -euo pipefail
REPO="${REPO:-Hyena-App/hyena}"

command -v gh >/dev/null || { print "Install the GitHub CLI first: brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || { print "Log in first: gh auth login"; exit 1; }

identity="$(security find-identity -v -p codesigning | grep -m1 'Developer ID Application' | sed -E 's/.*"(.*)"/\1/' || true)"
team="$(print -r -- "$identity" | sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p')"
[[ -n "$identity" ]] && print "Found identity: $identity"

print -n "Path to the exported Developer ID .p12: "; read -r p12
p12="${p12/#\~/$HOME}"
[[ -f "$p12" ]] || { print "No file at $p12"; exit 1; }
print -n ".p12 password (hidden): "; read -rs p12pass; print
# Check the password before uploading anything.
openssl pkcs12 -in "$p12" -passin "pass:$p12pass" -noout 2>/dev/null \
  || openssl pkcs12 -legacy -in "$p12" -passin "pass:$p12pass" -noout 2>/dev/null \
  || { print "That password doesn't open the .p12."; exit 1; }

print -n "Path to the App Store Connect API key (.p8): "; read -r p8
p8="${p8/#\~/$HOME}"
[[ -f "$p8" ]] || { print "No file at $p8"; exit 1; }
print -n "Key ID: "; read -r keyid
print -n "Issuer ID: "; read -r issuer
if [[ -z "$team" ]]; then print -n "Apple Team ID: "; read -r team; fi

base64 -i "$p12" | gh secret set DEVELOPER_ID_CERTIFICATE_P12 -R "$REPO"
print -rn -- "$p12pass" | gh secret set DEVELOPER_ID_CERTIFICATE_PASSWORD -R "$REPO"
base64 -i "$p8" | gh secret set NOTARY_KEY_P8 -R "$REPO"
print -rn -- "$keyid" | gh secret set NOTARY_KEY_ID -R "$REPO"
print -rn -- "$issuer" | gh secret set NOTARY_ISSUER_ID -R "$REPO"
print -rn -- "$team" | gh secret set APPLE_TEAM_ID -R "$REPO"
unset p12pass

print "\nSecrets set on $REPO:"
gh secret list -R "$REPO"
print "\nYou can delete the exported .p12 now if you don't need it elsewhere."
