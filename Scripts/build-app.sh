#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${ARCH:-$(uname -m)}"
APP="${APP_PATH:-$ROOT/dist/PastePilot-$ARCH.app}"
CONTENTS="$APP/Contents"
FRAMEWORKS="$CONTENTS/Frameworks"
BUILD_ROOT="$ROOT/.build/$ARCH"
RELEASE="$BUILD_ROOT/$ARCH-apple-macosx/release"
VERSION="${VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

case "$ARCH" in
  arm64|x86_64) ;;
  *)
    printf 'ARCH must be arm64 or x86_64: %s\n' "$ARCH" >&2
    exit 1
    ;;
esac

case "$VERSION" in
  *[!0-9A-Za-z.-]*|'')
    printf 'Invalid VERSION: %s\n' "$VERSION" >&2
    exit 1
    ;;
esac

case "$BUILD_NUMBER" in
  *[!0-9]*|'')
    printf 'BUILD_NUMBER must be a positive integer: %s\n' "$BUILD_NUMBER" >&2
    exit 1
    ;;
esac

cd "$ROOT"
swift build \
  -c release \
  --scratch-path "$BUILD_ROOT" \
  --triple "$ARCH-apple-macosx14.0"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$FRAMEWORKS"
cp "$RELEASE/PastePilot" "$CONTENTS/MacOS/PastePilot"
install_name_tool -add_rpath @loader_path/../Frameworks "$CONTENTS/MacOS/PastePilot"
lipo "$CONTENTS/MacOS/PastePilot" -verify_arch "$ARCH"
ditto "$RELEASE/Sparkle.framework" "$FRAMEWORKS/Sparkle.framework"
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
cp "$ROOT/Resources/AppIconSource.png" "$CONTENTS/Resources/AppIconSource.png"
cp "$ROOT/Resources/MenuBarIconTemplate.png" "$CONTENTS/Resources/MenuBarIconTemplate.png"

BUNDLE="$RELEASE/PastePilot_PastePilot.bundle"
if [ -d "$BUNDLE" ]; then
  cp -R "$BUNDLE" "$CONTENTS/Resources/"
fi

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>zh-Hans</string>
  </array>
  <key>CFBundleExecutable</key>
  <string>PastePilot</string>
  <key>CFBundleIdentifier</key>
  <string>space.beacox.PastePilot</string>
  <key>CFBundleName</key>
  <string>PastePilot</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>VERSION_PLACEHOLDER</string>
  <key>CFBundleVersion</key>
  <string>BUILD_NUMBER_PLACEHOLDER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSUIElement</key>
  <true/>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUPublicEDKey</key>
  <string>Cm3lFikkHbq9yccPqIT4UdO8Al75R/J8BORLEYvSWeI=</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright 2026 BeaCox</string>
</dict>
</plist>
PLIST

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"

if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --deep --sign - "$APP"
  SIGNING_DESCRIPTION="ad-hoc"
else
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$APP"
  SIGNING_DESCRIPTION="$SIGN_IDENTITY"
fi

codesign --verify --deep --strict --verbose=2 "$APP"
printf 'Built %s for %s (version %s, build %s, signed with %s)\n' \
  "$APP" "$ARCH" "$VERSION" "$BUILD_NUMBER" "$SIGNING_DESCRIPTION"
