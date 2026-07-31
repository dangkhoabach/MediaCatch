#!/usr/bin/env bash
# Fetches the yt-dlp standalone binary used as a Tauri sidecar (src-tauri/binaries/).
# Not committed to git (see src-tauri/.gitignore) since it's large and changes
# with every yt-dlp release — the app also self-updates its own copy at
# runtime (see src-tauri/src/ytdlp.rs), this is only the offline-capable seed.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p src-tauri/binaries

echo "Downloading yt-dlp_macos (universal arm64+x86_64)..."
curl -L -o src-tauri/binaries/yt-dlp-aarch64-apple-darwin \
  "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
cp src-tauri/binaries/yt-dlp-aarch64-apple-darwin src-tauri/binaries/yt-dlp-x86_64-apple-darwin
chmod +x src-tauri/binaries/yt-dlp-aarch64-apple-darwin src-tauri/binaries/yt-dlp-x86_64-apple-darwin

echo "Done: $(src-tauri/binaries/yt-dlp-aarch64-apple-darwin --version)"
