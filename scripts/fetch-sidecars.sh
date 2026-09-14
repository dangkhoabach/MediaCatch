#!/usr/bin/env bash
# Fetches the yt-dlp and ffmpeg binaries bundled into the app's
# Contents/Resources/bin (vendor/binaries/). Not committed to git (see
# .gitignore) since they're large and change with every release — yt-dlp
# also self-updates its own copy at runtime, this is only the
# offline-capable seed.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p vendor/binaries

echo "Downloading yt-dlp_macos (universal arm64+x86_64)..."
curl -L -o vendor/binaries/yt-dlp-aarch64-apple-darwin \
  "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"

# Verify against the checksum file published alongside the same release,
# exactly like the app's own runtime self-updater (YtdlpUpdater) does — this
# binary gets bundled into every build, so a bad download must fail the
# release rather than ship. The `$` anchor keeps the yt-dlp_macos.zip line
# from matching.
echo "Verifying yt-dlp checksum..."
curl -fsSL -o /tmp/yt-dlp-SHA2-256SUMS \
  "https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS"
EXPECTED_YTDLP_SHA=$(grep ' yt-dlp_macos$' /tmp/yt-dlp-SHA2-256SUMS | awk '{print $1}')
ACTUAL_YTDLP_SHA=$(shasum -a 256 vendor/binaries/yt-dlp-aarch64-apple-darwin | awk '{print $1}')
rm -f /tmp/yt-dlp-SHA2-256SUMS
if [ -z "$EXPECTED_YTDLP_SHA" ]; then
  echo "Error: no yt-dlp_macos entry in the release's SHA2-256SUMS" >&2
  exit 1
fi
if [ "$EXPECTED_YTDLP_SHA" != "$ACTUAL_YTDLP_SHA" ]; then
  echo "Error: yt-dlp checksum mismatch (expected $EXPECTED_YTDLP_SHA, got $ACTUAL_YTDLP_SHA)" >&2
  rm -f vendor/binaries/yt-dlp-aarch64-apple-darwin
  exit 1
fi

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
