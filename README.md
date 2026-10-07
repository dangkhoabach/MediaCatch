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
- Sparkle for auto-updates (EdDSA-signed), self-distributed outside the Mac App
  Store. Builds are ad-hoc signed and not notarized until there is an Apple
  Developer ID (see `docs/release.md`).
- **`DKBDownloaderNative.xcodeproj`** — committed as-is (only
  `project.pbxproj` is tracked); targets, build phases and `Info.plist` are
  edited in Xcode.

## Project structure

```
DKBDownloaderNative.xcodeproj/  Xcode project (targets, Sparkle pin, sidecar bundling phase)
DKBDownloaderApp/     App target: SwiftUI views, App/AppKit glue; Info.plist holds the version + Sparkle keys
DKBDownloaderCore/    Swift Package: models, DB, download engine, tests
scripts/              fetch-sidecars.sh (downloads yt-dlp/ffmpeg seed binaries), release.sh (local build, ad-hoc sign, Sparkle signature),
                      ui-click.swift (real mouse clicks for verifying the UI from a script; see its header)
vendor/binaries/      Sidecar binary seed (gitignored, fetched locally)
docs/                 Design/porting notes, release process
```

## Building

```bash
./scripts/fetch-sidecars.sh   # first time only, or to refresh yt-dlp/ffmpeg
xcodebuild -project DKBDownloaderNative.xcodeproj -scheme DKBDownloaderApp -configuration Debug build
```

See `docs/release.md` for the release and signing process.
