#!/bin/bash
# Signs, notarizes and publishes PadDeck for Mac as a GitHub release.
#   ./mac-agent/release.sh 1.3        (version = the tag, without the "v")
# Needs: the "Developer ID Application" certificate and the notarytool profile "paddeck-notary"
# (xcrun notarytool store-credentials paddeck-notary --apple-id … --team-id …).
set -uo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
[[ -n "$VERSION" ]] || { echo "uso: ./mac-agent/release.sh <versão>  (ex.: 1.3)"; exit 1; }
PROFILE="${NOTARY_PROFILE:-paddeck-notary}"
fail() { printf '\033[31m✗ %s\033[0m\n' "$*"; exit 1; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$*"; }

[[ "$(security find-identity -v -p codesigning)" == *"Developer ID Application"* ]] \
  || fail "falta o certificado Developer ID Application (Xcode › Settings › Accounts › Manage Certificates)"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || fail "falta o perfil '$PROFILE' do notarytool (veja o comentário no topo do script)"

PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' mac-agent/Info.plist)"
[[ "$PLIST_VERSION" == "$VERSION" ]] || fail "mac-agent/Info.plist está na versão $PLIST_VERSION, não $VERSION"

./mac-agent/build.sh notarize || fail "a notarização falhou (detalhes acima)"

NOTES="**PadDeck for Mac works together with the PadDeck app on your iPhone or iPad**: on its own it does nothing. Get the iPhone/iPad app on the [App Store](https://apps.apple.com/app/id6838387257) (or, for old jailbroken iPads, in the Cydia repo [douugr.github.io/repo](https://douugr.github.io/repo/)).

**O PadDeck para Mac funciona junto com o app PadDeck do iPhone ou iPad**: sozinho, ele não faz nada. Baixe o app do iPhone/iPad na [App Store](https://apps.apple.com/app/id6838387257).

---

Signed with Developer ID and notarized by Apple. Download PadDeck-mac.zip, unzip it and move PadDeck to Applications. macOS 12 or later, Apple silicon and Intel."

if gh release view "v$VERSION" >/dev/null 2>&1; then
  gh release upload "v$VERSION" mac-agent/build/PadDeck-mac.zip --clobber && ok "zip do v$VERSION atualizado"
else
  gh release create "v$VERSION" mac-agent/build/PadDeck-mac.zip --target main \
    -t "PadDeck $VERSION for Mac" -n "$NOTES" && ok "release v$VERSION publicado"
fi
