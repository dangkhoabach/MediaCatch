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
PROJECT_YML="project.yml"
SPARKLE_ACCOUNT="dkb-downloader"
SPARKLE_VERSION="2.6.4"
SPARKLE_TOOLS_DIR=".sparkle-tools"

command -v create-dmg >/dev/null || { echo "Error: create-dmg not found. Run: brew install create-dmg" >&2; exit 1; }

if [ ! -f vendor/binaries/yt-dlp-aarch64-apple-darwin ] || [ ! -f vendor/binaries/ffmpeg-x86_64-apple-darwin ]; then
  echo "==> Fetching yt-dlp/ffmpeg sidecar binaries"
  ./scripts/fetch-sidecars.sh
fi

echo "==> Testing DKBDownloaderCore"
(cd DKBDownloaderCore && swift test)

# project.yml is the source of truth, not Info.plist - xcodegen fully
# regenerates Info.plist from project.yml's properties on every `generate`
# (it doesn't merge), so editing Info.plist directly gets silently
# discarded the moment this script runs `xcodegen generate` below.
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
CURRENT_VERSION=$(grep -m1 'CFBundleShortVersionString:' "$PROJECT_YML" | sed -E 's/.*CFBundleShortVersionString: *"?([^"]*)"?/\1/')
read -rp "Current version is $CURRENT_VERSION. New version (e.g. 2.0.1) [Enter to keep]: " INPUT
VERSION="${INPUT:-$CURRENT_VERSION}"
sed -i '' -E "s/(CFBundleShortVersionString: )\"?[^\"[:space:]]*\"?/\1\"$VERSION\"/" "$PROJECT_YML"
sed -i '' -E "s/(CFBundleVersion: )\"?[^\"[:space:]]*\"?/\1\"$VERSION\"/" "$PROJECT_YML"
echo "==> Releasing version $VERSION"

echo "==> Regenerating Xcode project"
xcodegen generate

OUT_DIR="release-output/$VERSION"
BUILD_DIR="$OUT_DIR/DerivedData"
mkdir -p "$OUT_DIR"

echo "==> Building (Release, ad-hoc signed)"
xcodebuild build \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM=""

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"

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
if [ ! -x "$SPARKLE_TOOLS_DIR/bin/sign_update" ]; then
  mkdir -p "$SPARKLE_TOOLS_DIR"
  curl -fsSL -o "$SPARKLE_TOOLS_DIR/sparkle.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
  tar -xf "$SPARKLE_TOOLS_DIR/sparkle.tar.xz" -C "$SPARKLE_TOOLS_DIR"
fi
# -p prints only the raw EdDSA signature (no "sparkle:edSignature=... length=..."
# wrapper) - that raw value is exactly what admin.dangkhoabach.vn's "Sparkle
# signature" upload field expects. --account must match the account this
# app's key was generated under (see docs/release.md) - omitting it would
# silently sign with DKB Monitor's default-account key instead, producing a
# signature the app's embedded SUPublicEDKey can never verify.
"$SPARKLE_TOOLS_DIR/bin/sign_update" -p --account "$SPARKLE_ACCOUNT" "$DMG_PATH" | tee "$DMG_PATH.sig"

echo ""
echo "==> Done. Upload these two files at https://admin.dangkhoabach.vn (app: dkb-downloader):"
echo "    Installer:         $DMG_PATH"
echo "    Sparkle signature:  $DMG_PATH.sig"
echo ""
echo "Reminder: this build is ad-hoc signed, not notarized (no paid Apple"
echo "Developer Program membership) - first launch needs right-click > Open"
echo "to bypass Gatekeeper, same as the old Tauri build."
