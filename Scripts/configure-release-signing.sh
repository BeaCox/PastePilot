#!/bin/sh
set -eu

if [ -z "${DEVELOPER_ID_CERTIFICATE_BASE64:-}" ]; then
  echo "Developer ID certificate secret is not configured; using ad-hoc signing."
  exit 0
fi

: "${DEVELOPER_ID_CERTIFICATE_PASSWORD:?Missing DEVELOPER_ID_CERTIFICATE_PASSWORD}"
: "${DEVELOPER_ID_SIGN_IDENTITY:?Missing DEVELOPER_ID_SIGN_IDENTITY}"

KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-$(uuidgen)}"
KEYCHAIN_PATH="${RUNNER_TEMP:-.}/pastepilot-signing.keychain-db"
CERTIFICATE_PATH="${RUNNER_TEMP:-.}/developer-id-application.p12"

if ! printf '%s' "$DEVELOPER_ID_CERTIFICATE_BASE64" \
  | base64 --decode > "$CERTIFICATE_PATH" 2>/dev/null; then
  printf '%s' "$DEVELOPER_ID_CERTIFICATE_BASE64" \
    | base64 -D > "$CERTIFICATE_PATH"
fi

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERTIFICATE_PATH" \
  -k "$KEYCHAIN_PATH" \
  -P "$DEVELOPER_ID_CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security
security set-key-partition-list \
  -S apple-tool:,apple: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH"

EXISTING_KEYCHAINS="$(security list-keychains -d user | tr -d '"')"
security list-keychains -d user -s "$KEYCHAIN_PATH" $EXISTING_KEYCHAINS

{
  echo "SIGN_IDENTITY=$DEVELOPER_ID_SIGN_IDENTITY"
  echo "PASTEPILOT_SIGNING_KEYCHAIN=$KEYCHAIN_PATH"
} >> "$GITHUB_ENV"

if [ -n "${APPLE_ID:-}" ] \
  && [ -n "${APPLE_TEAM_ID:-}" ] \
  && [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]; then
  xcrun notarytool store-credentials "PastePilotNotary" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD"
  echo "NOTARY_PROFILE=PastePilotNotary" >> "$GITHUB_ENV"
  echo "Developer ID signing and notarization are configured."
else
  echo "Developer ID signing is configured; notarization secrets are incomplete."
fi
