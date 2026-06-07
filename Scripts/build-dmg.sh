#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/PastePilot.app"
STAGING="$ROOT/.build/dmg-root"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

cleanup() {
  rm -rf "$STAGING"
}
trap cleanup EXIT INT TERM

sh "$ROOT/Scripts/build-app.sh"

VERSION=$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' \
  "$APP/Contents/Info.plist")
DMG="${DMG_PATH:-$ROOT/dist/PastePilot-$VERSION.dmg}"
VOLUME_NAME="${VOLUME_NAME:-PastePilot $VERSION}"

mkdir -p "$(dirname "$DMG")"
rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/PastePilot.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
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
