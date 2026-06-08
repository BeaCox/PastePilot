#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${ARCH:-$(uname -m)}"
APP="${APP_PATH:-$ROOT/dist/PastePilot-$ARCH.app}"
DMG_ASSETS="$ROOT/.build/dmg-assets-$ARCH"
DMG_TOOLS="$ROOT/.build/dmgbuild-tools-1.6.7"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

cleanup() {
  rm -rf "$DMG_ASSETS"
}
trap cleanup EXIT INT TERM

sh "$ROOT/Scripts/build-app.sh"

VERSION=$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' \
  "$APP/Contents/Info.plist")
DMG="${DMG_PATH:-$ROOT/dist/PastePilot-$VERSION-$ARCH.dmg}"
VOLUME_NAME="${VOLUME_NAME:-PastePilot $VERSION ($ARCH)}"

mkdir -p "$(dirname "$DMG")"
rm -rf "$DMG_ASSETS"
mkdir -p "$DMG_ASSETS"
swift "$ROOT/Scripts/generate-dmg-background.swift" \
  "$DMG_ASSETS/background.png" 1
swift "$ROOT/Scripts/generate-dmg-background.swift" \
  "$DMG_ASSETS/background@2x.png" 2
rm -f "$DMG"

if ! PYTHONPATH="$DMG_TOOLS" python3 -c 'import dmgbuild' 2>/dev/null; then
  rm -rf "$DMG_TOOLS"
  python3 -m pip install \
    --quiet \
    --disable-pip-version-check \
    --target "$DMG_TOOLS" \
    "dmgbuild==1.6.7" \
    "ds_store==1.3.2" \
    "mac_alias==2.2.3"
fi

PYTHONPATH="$DMG_TOOLS" python3 -m dmgbuild \
  -s "$ROOT/Scripts/dmg-settings.py" \
  -D "app=$APP" \
  -D "background=$DMG_ASSETS/background.png" \
  --detach-retries 10 \
  "$VOLUME_NAME" \
  "$DMG"

if [ "$SIGN_IDENTITY" != "-" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  codesign --verify --verbose=2 "$DMG"
fi

hdiutil verify "$DMG"

if [ -n "$NOTARY_PROFILE" ]; then
  if [ "$SIGN_IDENTITY" = "-" ]; then
    printf 'NOTARY_PROFILE requires a Developer ID SIGN_IDENTITY.\n' >&2
    exit 1
  fi
  xcrun notarytool submit "$DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

printf 'Built %s\n' "$DMG"
