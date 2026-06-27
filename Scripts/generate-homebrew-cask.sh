#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 VERSION SHA256SUMS" >&2
  exit 64
fi

VERSION="$1"
CHECKSUMS="$2"

case "$VERSION" in
  v*)
    VERSION="${VERSION#v}"
    ;;
esac

ARM_SHA="$(
  awk -v version="$VERSION" '
    $2 == "PastePilot-" version "-arm64.dmg" { print $1 }
  ' "$CHECKSUMS"
)"
INTEL_SHA="$(
  awk -v version="$VERSION" '
    $2 == "PastePilot-" version "-x86_64.dmg" { print $1 }
  ' "$CHECKSUMS"
)"

if [ -z "$ARM_SHA" ] || [ -z "$INTEL_SHA" ]; then
  echo "Could not find both architecture checksums in $CHECKSUMS" >&2
  exit 1
fi

cat <<CASK
cask "pastepilot" do
  version "$VERSION"
  arch arm: "arm64", intel: "x86_64"

  sha256 arm:   "$ARM_SHA",
         intel: "$INTEL_SHA"

  url "https://github.com/BeaCox/PastePilot/releases/download/v#{version}/PastePilot-#{version}-#{arch}.dmg"
  name "PastePilot"
  desc "Local-first macOS clipboard manager for developer content"
  homepage "https://github.com/BeaCox/PastePilot"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "PastePilot.app"

  zap trash: [
    "~/Library/Application Support/PastePilot",
    "~/Library/Preferences/space.beacox.PastePilot.plist",
  ]
end
CASK
