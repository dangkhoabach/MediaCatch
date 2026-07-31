# Third-Party Notices

This app bundles the following third-party binaries as Tauri sidecars
(`src-tauri/binaries/`, fetched via `scripts/fetch-sidecars.sh`, not part of
this repo's own source).

## yt-dlp

- Source: https://github.com/yt-dlp/yt-dlp
- License: [Unlicense](https://github.com/yt-dlp/yt-dlp/blob/master/LICENSE) (public domain)
- No redistribution obligations.

## ffmpeg

- Build source: https://evermeet.cx/ffmpeg/ (static macOS binary, x86_64 —
  evermeet.cx does not publish arm64 builds; runs via Rosetta 2 on Apple
  Silicon)
- Upstream project: https://ffmpeg.org/
- **License: GPL v3** (this specific build is compiled with `--enable-gpl
  --enable-version3` and includes GPL-licensed components such as libx264/libx265)

Because this build is GPL-licensed, redistributing it requires making the
corresponding source available. FFmpeg's source is public
(https://ffmpeg.org/download.html, https://git.ffmpeg.org/ffmpeg.git) and
evermeet.cx documents the exact build configuration used for each release at
https://evermeet.cx/ffmpeg/ — this notice serves as the required offer of
source access for the exact ffmpeg binary bundled with this app.

**If DKB Downloader is ever distributed as closed-source or under a
non-GPL-compatible license, this ffmpeg dependency needs to either be
swapped for an LGPL-only build (drop `--enable-gpl`/`--enable-version3`
components like libx264) or be re-evaluated with legal advice before
release.**
