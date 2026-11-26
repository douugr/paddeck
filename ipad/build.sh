#!/bin/bash
# PadDeck for iPad (iOS 8, armv7, jailbroken). Same setup as MD16/SNES16:
#   export X13=/path/to/Xcode-13.4.1.app/Contents/Developer   # default: ../Xcode-13.4.1.app
#   export IPAD=192.168.x.x                                    # the iPad's IP
#
#   ./build.sh            builds build/PadDeck.app
#   ./build.sh install    builds and installs on the iPad over SSH
#   ./build.sh deb        builds build/com.douglasneto.paddeck_<version>_iphoneos-arm.deb for the Cydia repo
set -euo pipefail
cd "$(dirname "$0")"
exec > >(tee build.log) 2>&1   # keep a copy of the output for debugging

if [[ -z "${X13:-}" ]]; then
  # look next to this project, one level up, and next to the other iPad apps
  for c in .. ../.. ../../ipad-apps ~/Developer/ipad-apps ~/Developer /Applications; do
    if [[ -d "$c/Xcode-13.4.1.app" ]]; then X13="$(cd "$c" && pwd)/Xcode-13.4.1.app/Contents/Developer"; break; fi
  done
  X13="${X13:-$(cd .. && pwd)/Xcode-13.4.1.app/Contents/Developer}"
fi
SDK="$X13/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
CLANG="$X13/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
SSH_OPTS="${SSH_OPTS:--o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa}"

[[ -x "$CLANG" ]] || { echo "clang not found in X13=$X13 (export X13=/path/to/Xcode-13.4.1.app/Contents/Developer)"; exit 1; }

APP=build/PadDeck.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)

build() {
  rm -rf "$APP"
  mkdir -p "$APP"
  "$CLANG" -arch armv7 -miphoneos-version-min=8.0 -isysroot "$SDK" \
    -fobjc-arc -O2 -Wall -Wno-unguarded-availability-new -Wno-unguarded-availability \
    -I../crypto src/*.m ../crypto/pdcrypto.c ../crypto/monocypher.c \
    -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework AudioToolbox \
    -o "$APP/PadDeck"
  cp Info.plist "$APP/"
  cp resources/*.png "$APP/"
  printf 'APPL????' > "$APP/PkgInfo"
  # SpringBoard runs as "mobile": every file must be world-readable
  find "$APP" -type d -exec chmod 755 {} +
  find "$APP" -type f -exec chmod 644 {} +
  chmod 755 "$APP/PadDeck"
  if command -v ldid >/dev/null; then ldid -S "$APP/PadDeck"; else codesign -f -s - "$APP/PadDeck"; fi
  echo "OK: $APP"
}

install_app() {
  [[ -n "${IPAD:-}" ]] || { echo "set IPAD=<iPad IP>"; exit 1; }
  # tar over ssh: works with the old OpenSSH on iOS 8 (no sftp needed)
  # no ._ AppleDouble files / xattrs from macOS; -m ignores the iPad's clock skew
  COPYFILE_DISABLE=1 tar --no-mac-metadata --no-xattrs -C build -cf - PadDeck.app | ssh $SSH_OPTS root@"$IPAD" '
    rm -rf /Applications/PadDeck.app /Applications/Remote16.app /Applications/._Remote16.app &&
    tar -C /Applications -xmf - &&
    chown -R root:wheel /Applications/PadDeck.app &&
    find /Applications/PadDeck.app -type d -exec chmod 755 {} + &&
    find /Applications/PadDeck.app -type f -exec chmod 644 {} + &&
    chmod 755 /Applications/PadDeck.app/PadDeck &&
    su mobile -c uicache'
  echo "Installed on $IPAD"
}

make_deb() {
  command -v dpkg-deb >/dev/null || { echo "dpkg-deb missing: brew install dpkg"; exit 1; }
  local root=build/deb
  rm -rf "$root"
  mkdir -p "$root/Applications" "$root/DEBIAN"
  cp -R "$APP" "$root/Applications/"
  sed "s/@VERSION@/$VERSION/" deb/control > "$root/DEBIAN/control"
  cp deb/postinst deb/postrm "$root/DEBIAN/"
  chmod 755 "$root/DEBIAN/postinst" "$root/DEBIAN/postrm"
  # strip macOS metadata, gzip for the old dpkg in Cydia
  find "$root" -name .DS_Store -delete
  local out="build/com.douglasneto.paddeck_${VERSION}_iphoneos-arm.deb"
  COPYFILE_DISABLE=1 dpkg-deb -Zgzip --root-owner-group -b "$root" "$out"
  echo "OK: $out"
}

diag() {
  [[ -n "${IPAD:-}" ]] || { echo "set IPAD=<iPad IP>"; exit 1; }
  ssh $SSH_OPTS root@"$IPAD" '
    echo "== /Applications"; ls -la /Applications | grep -i -e pad -e remote
    echo "== app"; ls -la /Applications/PadDeck.app
    echo "== uicache"; which uicache; su mobile -c "uicache" 2>&1; echo "exit $?"
    echo "== installation cache"
    for f in /var/mobile/Library/Caches/com.apple.mobile.installation.plist /var/mobile/Library/Caches/com.apple.LaunchServices*; do
      [ -e "$f" ] && echo "$f: $(grep -a -c com.douglasneto.paddeck "$f") paddeck, $(grep -a -c com.douugr.remote16 "$f") remote16"
    done
    echo "== icon state"; grep -a -c paddeck /var/mobile/Library/SpringBoard/IconState.plist 2>/dev/null
    echo "== plist"; plutil /Applications/PadDeck.app/Info.plist 2>&1 | head -30
  '
}

case "${1:-}" in
  diag) diag; exit 0 ;;
esac

build
case "${1:-}" in
  install) install_app ;;
  deb) make_deb ;;
  "") ;;
  *) echo "unknown command: $1"; exit 1 ;;
esac
