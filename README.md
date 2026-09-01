# DKB Downloader

A personal, native macOS app for downloading video/audio/images from
YouTube, Facebook, Instagram, TikTok, X, and anywhere else `yt-dlp`
supports — format selection, batch downloads, a download queue, library/
history, and a watch-folder feature for auto-downloading new uploads from
a channel.

## Tech stack

- **Swift 6, SwiftUI/AppKit**, macOS 14+ (Sonoma).
- **`DKBDownloaderCore`** (Swift Package, headless): models, GRDB.swift
  storage, `yt-dlp`/`ffmpeg` process management, playlist/URL parsing,
  watch-folder scheduling.
- Bundles `yt-dlp` and `ffmpeg` as sidecar binaries (see
  `THIRD-PARTY-NOTICES.md`).
- Sparkle for auto-updates, notarized + Developer ID signed for
  self-distribution outside the Mac App Store.

## Project structure

```
native/
  DKBDownloaderApp/     App target: SwiftUI views, App/AppKit glue
  DKBDownloaderCore/    Swift Package: models, DB, download engine, tests
  scripts/              fetch-sidecars.sh (downloads yt-dlp/ffmpeg seed binaries)
  vendor/binaries/      Sidecar binary seed (gitignored, fetched locally/in CI)
  docs/                 Release process, port plan
docs/                   Design/porting notes
```

## Building

```bash
cd native
./scripts/fetch-sidecars.sh   # first time only, or to refresh yt-dlp/ffmpeg
xcodegen generate
xcodebuild -project DKBDownloaderNative.xcodeproj -scheme DKBDownloaderApp -configuration Debug build
```

See `native/docs/release.md` for the release/signing/notarization process.
