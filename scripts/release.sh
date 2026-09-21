#!/usr/bin/env bash
# Builds, ad-hoc signs, DMGs, and Sparkle-signs DKB Downloader entirely on
# this machine — no CI, no GitHub Actions secrets. Same manual-release model
# the old Tauri app used (see docs/release.md): no Apple Developer Program
# membership, so no Developer ID signing and no notarization — same
# ad-hoc-signed, "right-click > Open on first launch" distribution the
# Tauri build already shipped.
#
# One-time setup (see docs/release.md):
#   - A Sparkle EdDSA keypair generated under the `dkb-downloader` Keychain
#     account (kept distinct from DKB Monitor's, which uses the default
#     account) — see docs/release.md for the exact one-time generate_keys
#     command.
#   - `brew install create-dmg` (styles the installer DMG's Finder window -
#     icon layout + Applications drop link - instead of hdiutil's bare copy).
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="DKBDownloaderApp"
PROJECT="DKBDownloaderNative.xcodeproj"
APP_NAME="DKB Downloader"
INFO_PLIST="DKBDownloaderApp/Info.plist"
SPARKLE_ACCOUNT="dkb-downloader"
SPARKLE_VERSION="2.6.4"
# SHA-256 of Sparkle-2.6.4.tar.xz. Pinned so the tools this script signs
# releases with can't be swapped out from under it later; it was computed
# from a download here, which means it guards against future substitution at
# that URL, not against that first download having already been tampered
# with. Must be recomputed when SPARKLE_VERSION changes.
SPARKLE_SHA256="50612a06038abc931f16011d7903b8326a362c1074dabccb718404ce8e585f0b"
SPARKLE_TOOLS_DIR=".sparkle-tools"

command -v create-dmg >/dev/null || { echo "Error: create-dmg not found. Run: brew install create-dmg" >&2; exit 1; }

if [ ! -f vendor/binaries/yt-dlp-aarch64-apple-darwin ] || [ ! -f vendor/binaries/ffmpeg-x86_64-apple-darwin ]; then
  echo "==> Fetching yt-dlp/ffmpeg sidecar binaries"
  ./scripts/fetch-sidecars.sh
fi

# fetch-sidecars.sh verifies what it downloads, but it only runs when the
# files are missing — a binary already sitting in vendor/binaries (from an
# older, unverified fetch, or from anywhere at all) would otherwise be bundled
# as-is. Check it against the same pin before it goes into a release.
# shellcheck source=sidecar-pins.sh
source ./scripts/sidecar-pins.sh
echo "==> Verifying bundled ffmpeg against scripts/sidecar-pins.sh"
ACTUAL_FFMPEG_BINARY_SHA=$(shasum -a 256 vendor/binaries/ffmpeg-x86_64-apple-darwin | awk '{print $1}')
if [ "$FFMPEG_BINARY_SHA256" != "$ACTUAL_FFMPEG_BINARY_SHA" ]; then
  echo "Error: vendor/binaries/ffmpeg-x86_64-apple-darwin is not the pinned ffmpeg $FFMPEG_VERSION" >&2
  echo "  expected $FFMPEG_BINARY_SHA256" >&2
  echo "  got      $ACTUAL_FFMPEG_BINARY_SHA" >&2
  echo "Re-run scripts/fetch-sidecars.sh to replace it with a verified copy." >&2
  exit 1
fi

echo "==> Testing DKBDownloaderCore"
(cd DKBDownloaderCore && swift test)

# Info.plist is the source of truth for the version.
#
# Both CFBundleShortVersionString and CFBundleVersion get set to the exact
# same MAJOR.MINOR.PATCH string the user enters here, matching the
# sparkle:version/sparkle:shortVersionString pair admin.dangkhoabach.vn's
# upload form writes into the appcast. An earlier version of this script
# split the input into a 2-component marketing version plus a separate
# build number (e.g. "2.0.1" -> version "2.0", build "1") - typing "2.0.1"
# for a second release produced the exact same CFBundleVersion ("1") as the
# very first "2.0" release, so Sparkle could never tell the two apart and
# kept reporting an update as available even once the user was already on
# the latest DMG.
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")
SUGGESTED_VERSION=$(awk -F. '{print $1"."$2"."$3+1}' <<< "$CURRENT_VERSION")
read -rp "Current version is $CURRENT_VERSION. New version (e.g. $SUGGESTED_VERSION) [Enter to keep]: " INPUT
VERSION="${INPUT:-$CURRENT_VERSION}"

# The version goes into a PlistBuddy command and ends up in a filename, so
# anything but three plain numbers is rejected before it can do damage: a
# path separator would write the DMG somewhere unintended.
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Error: version must be MAJOR.MINOR.PATCH (digits only), got \"$VERSION\"." >&2
  exit 1
}

# Sparkle decides "is there an update" by comparing versions, so shipping a
# lower number than what is already published leaves every existing install
# quietly stuck — no error anywhere, just an update nobody is ever offered.
if [ "$VERSION" != "$CURRENT_VERSION" ] &&
   [ "$(printf '%s\n%s\n' "$CURRENT_VERSION" "$VERSION" | sort -V | tail -1)" != "$VERSION" ]; then
  echo "Error: $VERSION is lower than the current $CURRENT_VERSION." >&2
  exit 1
fi

# Info.plist is edited in place before the build, so any failure from here
# on would otherwise leave it bumped to a version that never shipped.
INFO_PLIST_BACKUP=$(mktemp)
cp "$INFO_PLIST" "$INFO_PLIST_BACKUP"

# One handler, installed once: `$?` inside a trap is whatever ran last, so
# chaining two traps would have the second read the first's exit code.
on_exit() {
  local status=$?
  if [ -n "${BUILD_DIR:-}" ]; then
    rm -rf "$BUILD_DIR"
  fi
  if [ "$status" -ne 0 ]; then
    echo "==> Failed (exit $status) — restoring $INFO_PLIST" >&2
    cp "$INFO_PLIST_BACKUP" "$INFO_PLIST"
  fi
  rm -f "$INFO_PLIST_BACKUP"
}
trap on_exit EXIT

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" "$INFO_PLIST"
echo "==> Releasing version $VERSION"

OUT_DIR="release-output/$VERSION"
mkdir -p "$OUT_DIR"

# Outside release-output, and removed on the way out: keeping DerivedData
# next to the DMG left roughly a gigabyte behind per release. The DMG and
# its signature are the only two files worth keeping.
BUILD_DIR=$(mktemp -d)

echo "==> Building (Release, ad-hoc signed, universal arm64+x86_64)"
# Without an explicit -destination, xcodebuild resolves the implicit "My
# Mac" destination and only builds for that Mac's own architecture,
# ignoring the project's ARCHS setting - producing an arm64-only binary on
# an Apple Silicon build machine, unusable on Intel Macs. The generic
# platform destination makes it build for every arch in ARCHS instead.
xcodebuild build \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -destination "generic/platform=macOS" -quiet \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM=""

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"

# Everything below packages and signs whatever sits at APP_PATH without ever
# looking at it. A build that silently produced nothing, or produced an
# arm64-only binary, would still yield a DMG with a valid EdDSA signature —
# one that simply doesn't launch on the Macs it was meant for.
echo "==> Verifying the built app"
[ -d "$APP_PATH" ] || { echo "Error: no app at $APP_PATH — the build produced nothing." >&2; exit 1; }

codesign --verify --deep --strict "$APP_PATH" || {
  echo "Error: $APP_PATH failed signature verification." >&2
  exit 1
}

ARCHS_BUILT=$(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME")
for arch in arm64 x86_64; do
  grep -qw "$arch" <<< "$ARCHS_BUILT" || {
    echo "Error: binary is missing $arch (built: $ARCHS_BUILT). Intel or Apple Silicon Macs would be left out." >&2
    exit 1
  }
done
echo "    architectures: $ARCHS_BUILT"

echo "==> Creating DMG"
DMG_PATH="$OUT_DIR/DKB-Downloader-$VERSION.dmg"
rm -f "$DMG_PATH"
create-dmg \
  --volname "$APP_NAME" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 160 185 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 460 185 \
  "$DMG_PATH" \
  "$APP_PATH"

echo "==> Signing update with Sparkle"
# Cached per version: guarding only on "is sign_update present" meant bumping
# SPARKLE_VERSION silently kept signing with the previous release's tools.
SPARKLE_TOOLS_DIR="$SPARKLE_TOOLS_DIR/$SPARKLE_VERSION"
if [ ! -x "$SPARKLE_TOOLS_DIR/bin/sign_update" ]; then
  mkdir -p "$SPARKLE_TOOLS_DIR"
  curl -fsSL -o "$SPARKLE_TOOLS_DIR/sparkle.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
  ACTUAL_SPARKLE_SHA=$(shasum -a 256 "$SPARKLE_TOOLS_DIR/sparkle.tar.xz" | awk '{print $1}')
  if [ "$ACTUAL_SPARKLE_SHA" != "$SPARKLE_SHA256" ]; then
    echo "Error: Sparkle tarball checksum mismatch" >&2
    echo "  expected $SPARKLE_SHA256" >&2
    echo "  got      $ACTUAL_SPARKLE_SHA" >&2
    rm -f "$SPARKLE_TOOLS_DIR/sparkle.tar.xz"
    exit 1
  fi
  tar -xf "$SPARKLE_TOOLS_DIR/sparkle.tar.xz" -C "$SPARKLE_TOOLS_DIR"
fi
# -p prints only the raw EdDSA signature (no "sparkle:edSignature=... length=..."
# wrapper) - that raw value is exactly what admin.dangkhoabach.vn's "Sparkle
# signature" upload field expects. --account must match the account this
# app's key was generated under (see docs/release.md) - omitting it would
# silently sign with DKB Monitor's default-account key instead, producing a
# signature the app's embedded SUPublicEDKey can never verify.
"$SPARKLE_TOOLS_DIR/bin/sign_update" -p --account "$SPARKLE_ACCOUNT" "$DMG_PATH" | tee "$DMG_PATH.sig"
[ -s "$DMG_PATH.sig" ] || { echo "Error: sign_update produced an empty signature." >&2; exit 1; }

# The upload is two separate form fields, so the DMG and the signature can be
# mismatched by hand — pairing a new installer with the previous release's
# signature makes every client reject the update with an error that points
# nowhere near the real cause. Printing the installer's own checksum gives
# something to compare against after uploading.
DMG_SHA256=$(shasum -a 256 "$DMG_PATH" | cut -d" " -f1)

echo ""
echo "==> Done. Upload these two files at https://admin.dangkhoabach.vn (app: dkb-downloader):"
echo "    Installer:         $DMG_PATH"
echo "    Sparkle signature:  $DMG_PATH.sig"
echo "    Installer SHA-256: $DMG_SHA256"
echo ""
echo "Reminder: this build is ad-hoc signed, not notarized (no paid Apple"
echo "Developer Program membership) - first launch needs right-click > Open"
echo "to bypass Gatekeeper, same as the old Tauri build."
