#!/usr/bin/env bash
# Fetches the yt-dlp and ffmpeg binaries bundled into the app's
# Contents/Resources/bin (native/vendor/binaries/). Not committed to git
# (see native/.gitignore) since they're large and change with every
# release — yt-dlp also self-updates its own copy at runtime, this is only
# the offline-capable seed.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p vendor/binaries

echo "Downloading yt-dlp_macos (universal arm64+x86_64)..."
curl -L -o vendor/binaries/yt-dlp-aarch64-apple-darwin \
  "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
cp vendor/binaries/yt-dlp-aarch64-apple-darwin vendor/binaries/yt-dlp-x86_64-apple-darwin
chmod +x vendor/binaries/yt-dlp-aarch64-apple-darwin vendor/binaries/yt-dlp-x86_64-apple-darwin
echo "  yt-dlp: $(vendor/binaries/yt-dlp-aarch64-apple-darwin --version)"

# evermeet.cx only publishes x86_64 builds (see ../THIRD-PARTY-NOTICES.md for
# why) — it runs fine under Rosetta 2 on Apple Silicon, same binary for both
# target-triple names.
echo "Downloading static ffmpeg (evermeet.cx, x86_64 — runs via Rosetta on Apple Silicon)..."
FFMPEG_URL=$(curl -s "https://evermeet.cx/ffmpeg/info/ffmpeg/release" | python3 -c "import json,sys; print(json.load(sys.stdin)['download']['zip']['url'])")
curl -L -o /tmp/ffmpeg-sidecar.zip "$FFMPEG_URL"
unzip -o /tmp/ffmpeg-sidecar.zip -d /tmp/ffmpeg-sidecar-extract
cp /tmp/ffmpeg-sidecar-extract/ffmpeg vendor/binaries/ffmpeg-aarch64-apple-darwin
cp /tmp/ffmpeg-sidecar-extract/ffmpeg vendor/binaries/ffmpeg-x86_64-apple-darwin
chmod +x vendor/binaries/ffmpeg-aarch64-apple-darwin vendor/binaries/ffmpeg-x86_64-apple-darwin
rm -rf /tmp/ffmpeg-sidecar.zip /tmp/ffmpeg-sidecar-extract
echo "  ffmpeg: $(vendor/binaries/ffmpeg-x86_64-apple-darwin -version | head -1)"
