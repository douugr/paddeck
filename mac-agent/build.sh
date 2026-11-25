#!/bin/bash
# Builds build/PadDeck.app (the Mac agent, universal arm64 + x86_64).
#   ./build.sh           build
#   ./build.sh install   build, copy to /Applications and open it
#   ./build.sh release   build and zip it as build/PadDeck-mac.zip for a GitHub release (ad-hoc signed)
#   ./build.sh notarize  like release, but signed with your Developer ID and notarized by Apple
set -euo pipefail
cd "$(dirname "$0")"
exec > >(tee build.log) 2>&1   # keep a copy of the output for debugging

APP=build/PadDeck.app
rm -rf "$APP" build/obj
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

for arch in arm64 x86_64; do
  xcrun swiftc -O \
    -target $arch-apple-macos12.0 \
    -framework Cocoa -framework Network -framework ServiceManagement \
    main.swift -o build/obj/PadDeck-$arch
done
lipo -create build/obj/PadDeck-arm64 build/obj/PadDeck-x86_64 -output "$APP/Contents/MacOS/PadDeck"

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "OK: $APP ($(lipo -archs "$APP/Contents/MacOS/PadDeck"))"

case "${1:-}" in
  install)
    pkill -x PadDeck 2>/dev/null && sleep 1 || true
    pkill -x Remote16 2>/dev/null || true          # old name
    rm -rf /Applications/PadDeck.app /Applications/Remote16.app
    cp -R "$APP" /Applications/
    open /Applications/PadDeck.app || { sleep 2; open /Applications/PadDeck.app; }
    echo "Installed in /Applications. If the cursor doesn't move, remove PadDeck from"
    echo "System Settings > Privacy & Security > Accessibility and add it again"
    echo "(ad-hoc signatures change on every build)."
    ;;
  notarize)
    # Signs with your Developer ID, notarizes with Apple and staples the ticket, then zips.
    # One-time setup: see the comment at the top of mac-agent/release.sh.
    IDENTITY="${DEVELOPER_ID:-Developer ID Application}"
    PROFILE="${NOTARY_PROFILE:-paddeck-notary}"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
    rm -f build/notarize.zip build/PadDeck-mac.zip
    ditto -c -k --keepParent "$APP" build/notarize.zip
    xcrun notarytool submit build/notarize.zip --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
    ditto -c -k --keepParent "$APP" build/PadDeck-mac.zip
    rm -f build/notarize.zip
    echo "OK: build/PadDeck-mac.zip (signed, notarized and stapled)"
    ;;
  release)
    rm -f build/PadDeck-mac.zip
    ditto -c -k --keepParent "$APP" build/PadDeck-mac.zip
    echo "OK: build/PadDeck-mac.zip"
    ;;
  "") ;;
  *) echo "unknown command: $1"; exit 1 ;;
esac
