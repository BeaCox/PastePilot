#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/PastePilot.app"
CONTENTS="$APP/Contents"
BUILD_ROOT="$ROOT/.build/universal"
ARM64_BUILD="$BUILD_ROOT/arm64"
X86_64_BUILD="$BUILD_ROOT/x86_64"
ARM64_RELEASE="$ARM64_BUILD/arm64-apple-macosx/release"
X86_64_RELEASE="$X86_64_BUILD/x86_64-apple-macosx/release"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

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
  --scratch-path "$ARM64_BUILD" \
  --triple arm64-apple-macosx14.0
swift build \
  -c release \
  --scratch-path "$X86_64_BUILD" \
  --triple x86_64-apple-macosx14.0

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
lipo -create \
  "$ARM64_RELEASE/PastePilot" \
  "$X86_64_RELEASE/PastePilot" \
  -output "$CONTENTS/MacOS/PastePilot"
lipo "$CONTENTS/MacOS/PastePilot" -verify_arch arm64 x86_64
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
cp "$ROOT/Resources/AppIconSource.png" "$CONTENTS/Resources/AppIconSource.png"
cp "$ROOT/Resources/MenuBarIconTemplate.png" "$CONTENTS/Resources/MenuBarIconTemplate.png"

BUNDLE="$ARM64_RELEASE/PastePilot_PastePilot.bundle"
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
printf 'Built %s (version %s, build %s, signed with %s)\n' \
  "$APP" "$VERSION" "$BUILD_NUMBER" "$SIGNING_DESCRIPTION"
