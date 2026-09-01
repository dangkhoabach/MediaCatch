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
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="DKBDownloaderApp"
PROJECT="DKBDownloaderNative.xcodeproj"
APP_NAME="DKB Downloader"
INFO_PLIST="DKBDownloaderApp/Info.plist"
SPARKLE_ACCOUNT="dkb-downloader"
SPARKLE_VERSION="2.6.4"
SPARKLE_TOOLS_DIR=".sparkle-tools"

if [ ! -f vendor/binaries/yt-dlp-aarch64-apple-darwin ] || [ ! -f vendor/binaries/ffmpeg-x86_64-apple-darwin ]; then
  echo "==> Fetching yt-dlp/ffmpeg sidecar binaries"
  ./scripts/fetch-sidecars.sh
fi

echo "==> Testing DKBDownloaderCore"
(cd DKBDownloaderCore && swift test)

CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
read -rp "Current version is $CURRENT_VERSION (build $CURRENT_BUILD). New version [Enter to keep]: " NEW_VERSION
VERSION="${NEW_VERSION:-$CURRENT_VERSION}"
NEW_BUILD=$((CURRENT_BUILD + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$INFO_PLIST"
echo "==> Releasing version $VERSION (build $NEW_BUILD)"

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
DMG_ROOT="$OUT_DIR/dmg-root"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R "$APP_PATH" "$DMG_ROOT/"
ln -sf /Applications "$DMG_ROOT/Applications"
DMG_PATH="$OUT_DIR/DKB-Downloader-$VERSION.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH"

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
