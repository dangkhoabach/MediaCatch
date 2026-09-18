# Releasing DKB Downloader (native, macOS)

This is the release process for the Swift app — see
`swift-native-port-plan.md` for the full port plan. Cutover is complete:
the old Tauri tree (`src/`, `src-tauri/`, `release/README.md`'s
admin-panel/per-machine/Windows process) has been removed, and the Swift
project itself was later flattened out of a `native/` wrapper folder to the
repo root (that folder existed only to sit alongside the Tauri tree during
the port). This is now the only release process for this app.

Everything runs locally on this Mac — no CI, no GitHub Actions secrets.
Same manual-publish model the old Tauri app used (build + sign locally,
then upload by hand to admin.dangkhoabach.vn): only the build tooling
changed (`xcodebuild`/`codesign`/Sparkle instead of `cargo tauri build`/
`tauri-plugin-updater`'s minisign).

No Apple Developer Program membership (the $99/year one) exists for this
project, same as the old Tauri build — so there's no Developer ID signing
and no notarization here. Builds are **ad-hoc signed** instead (free,
built into Xcode/`codesign`), which means end users have to right-click →
Open on first launch to get past Gatekeeper's "unidentified developer"
warning — the same experience the Tauri build already had. If a paid
membership is ever added later, `scripts/release.sh` would need a real
Developer ID identity + `xcrun notarytool` step added back in.

## One-time setup

1. **Sparkle EdDSA keypair** — already generated, under the `dkb-downloader`
   Keychain account (kept distinct from DKB Monitor's, which uses the
   default account); `SUPublicEDKey` in `project.yml` is already the real
   public key. Nothing to do here unless that key is ever rotated - if it
   ever needs regenerating, the exact command is:
   ```bash
   .sparkle-tools/bin/generate_keys --account dkb-downloader
   ```
   The `--account dkb-downloader` flag is **required** — omitting it falls
   back to the Keychain's default `ed25519` account, which is already
   occupied by DKB Monitor's key (Sparkle's own docs: "you only need one
   signing key, no matter how many apps you embed Sparkle in" — true in
   general, but this repo deliberately keeps a separate key per app for
   isolation).
2. **`create-dmg`** — styles the installer DMG's Finder window (icon layout,
   Applications drop link) instead of a bare `hdiutil` copy:
   ```bash
   brew install create-dmg
   ```
   No custom background image — a dark particle-network image was tried
   (`scripts/generate-dmg-background.py`) but Finder always draws icon name
   labels in black with no way to override that, so "DKB Downloader"/
   "Applications" were essentially unreadable against it. Back to Finder's
   plain default background, where the labels are legible.

`project.yml` deliberately does not set `SUEnableAutomaticChecks` (same as
DKB Monitor): leaving it out lets Sparkle show its own first-launch "check
automatically?" prompt and store the answer, which Settings › Updates then
reads and writes. Hardcoding it to `true` would skip that prompt and phone
home daily without asking. `AppDelegate` touches `AppUpdater.shared` at
launch so the scheduled check actually starts — the controller is lazy.

## Cutting a release

```bash
./scripts/release.sh
```

Fetches sidecar binaries if missing. Prompts for the version (e.g. `2.0.1`;
Enter keeps the current one), writes that exact string into both
`CFBundleShortVersionString` and `CFBundleVersion` in `project.yml` (the
actual source of truth — editing `Info.plist` directly gets silently
discarded by the next `xcodegen generate`), then runs: `swift test` →
`xcodegen generate` → ad-hoc-signed Release build (in a temporary
DerivedData, removed afterwards) → verify (signature, universal
arm64+x86_64) → DMG → Sparkle-sign (under the `dkb-downloader` account).
Output lands in `release-output/<version>/` (gitignored): the `.dmg` and
its `.sig` (the raw EdDSA signature, ready to paste as-is), plus the DMG's
SHA-256 printed for comparing after upload.

The version must be `MAJOR.MINOR.PATCH` and not lower than the current one
(Sparkle would never offer a lower one). If anything fails after the
version was written, `project.yml` is restored, so a failed run never
leaves a version behind that was never released.

Both version fields are always set identically — an earlier version of
this script split the input into a 2-component marketing version plus a
separate build number (`2.0.1` → version `2.0`, build `1`), which meant a
second release sharing the same `MAJOR.MINOR` reused the exact same
`CFBundleVersion` as the first, so Sparkle could never tell the two apart
and kept reporting an update as available even once the user was already
on the latest DMG.

## Uploading a release

Not automated — go to **admin.dangkhoabach.vn → Apps** and use "Publish new
app" (first release — slug `dkb-downloader`) or "Republish" (subsequent
releases), ticking macOS and uploading:

| Form field | File |
|---|---|
| Installer file | `DKB-Downloader-<version>.dmg` |
| Sparkle signature (.sig) | `DKB-Downloader-<version>.dmg.sig` (paste its contents) |

Leave "Updater bundle"/"Signature (.sig)" (the Tauri-format fields) empty —
this app never shipped a Tauri auto-updater. The admin panel writes
`updates.dangkhoabach.vn/dkb-downloader/appcast.xml` from the Sparkle
fields, which `SUFeedURL` in `project.yml` points at.

## Sidecar binaries (yt-dlp, ffmpeg)

Same seed binaries as the old Tauri build (D12 — bundled as-is, not
rebuilt): `project.yml`'s `postbuildScripts` copies
`vendor/binaries/yt-dlp-aarch64-apple-darwin` and
`ffmpeg-x86_64-apple-darwin` into `Contents/Resources/bin/` at build time.
`scripts/release.sh` runs `scripts/fetch-sidecars.sh` automatically if
`vendor/binaries/` is empty — ffmpeg has no self-update path, so a release
built without real binaries checked out ships without a working ffmpeg
(yt-dlp self-updates on first launch via `YtdlpUpdater`, so it's less
critical there).

Both binaries are checksum-verified: yt-dlp against the `SHA2-256SUMS` file
published with its release, ffmpeg against the version and SHA-256 pinned in
`scripts/sidecar-pins.sh` (evermeet.cx publishes only GPG signatures, no
checksum file, so the pin is kept here). `release.sh` re-checks the ffmpeg
already on disk against that same pin before building and refuses to
continue on a mismatch — so a binary that never went through
`fetch-sidecars.sh` can't end up in a DMG. To move to a newer ffmpeg, follow
the bump note at the top of `sidecar-pins.sh`.
