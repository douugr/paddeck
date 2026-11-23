#!/bin/bash
# Builds build/PadDeck.app (the Mac agent, universal arm64 + x86_64).
#   ./build.sh           build
#   ./build.sh install   build, copy to /Applications and open it
#   ./build.sh release   build and zip it as build/PadDeck-mac.zip for a GitHub release
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
  release)
    rm -f build/PadDeck-mac.zip
    ditto -c -k --keepParent "$APP" build/PadDeck-mac.zip
    echo "OK: build/PadDeck-mac.zip"
    ;;
  "") ;;
  *) echo "unknown command: $1"; exit 1 ;;
esac
