# Releasing DKB Downloader (native, macOS)

This is the release process for the Swift rewrite in `native/` — see
`../../docs/swift-native-port-plan.md` for the full port plan. Cutover is
complete: the old Tauri tree (`src/`, `src-tauri/`, `release/README.md`'s
admin-panel/per-machine/Windows process) has been removed. This is now the
only release process for this app.

## How it works

Pushing a `v*` tag triggers `.github/workflows/native-release.yml` on a
GitHub-hosted macOS runner: `swift test` → `xcodegen generate` → archive →
Developer ID sign → notarize + staple → DMG → Sparkle-sign + generate
`appcast.xml` → publish a GitHub Release with both files attached. Nothing
runs on a local machine — no per-platform build scripts, no manual upload
panel (there's no Windows build; this app is macOS-only, per D3/D11 in the
port plan).

`SUFeedURL` in `native/project.yml` already points at
`github.com/dangkhoabach/DKB-Downloader/releases/latest/download/appcast.xml`,
so once one release exists, Sparkle's "Check for Updates…" and the
scheduled background check both work automatically — no admin panel step.

## One-time setup (not done yet — see native-release.yml's header comment)

1. **Generate a Sparkle EdDSA keypair** — grab the `generate_keys` binary
   from a Sparkle release tarball (version must match `native/project.yml`'s
   pinned SPM version), run it, then:
   - Paste the printed public key into `SUPublicEDKey` in `native/project.yml`
     (currently the placeholder `REPLACE_WITH_GENERATED_ED25519_PUBLIC_KEY`).
   - Save the printed private key as the GitHub Actions secret
     `SPARKLE_ED_PRIVATE_KEY`.
   - This is a **new** keypair — not DKB Monitor's, and not the minisign key
     `tauri-plugin-updater` currently uses for this app's Tauri build.
2. **Add the remaining 7 repo secrets** (Settings → Secrets and variables →
   Actions): `APPLE_DEVELOPER_ID_CERT_P12_BASE64`,
   `APPLE_DEVELOPER_ID_CERT_PASSWORD`, `APPLE_TEAM_ID`,
   `APPLE_NOTARIZE_KEY_ID`, `APPLE_NOTARIZE_ISSUER_ID`,
   `APPLE_NOTARIZE_KEY_P8_BASE64`, `CI_KEYCHAIN_PASSWORD`.
3. Once both are done, `SUEnableAutomaticChecks` in `project.yml` can be
   flipped to `true` — it's `false` until a real feed exists, otherwise
   Sparkle pops an "Unable to Check for Updates" alert on every launch
   (same bug hit and fixed the same way in DKB Monitor).

## Cutting a release

1. Bump the version — `CFBundleShortVersionString`/`CFBundleVersion` in
   `native/DKBDownloaderApp/Info.plist` (currently hardcoded `1.0`/`1`, since
   no release has happened yet).
2. Commit the bump, then tag and push:
   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```
3. Watch the `Native (Swift) Release` workflow run in GitHub Actions. On
   success, the GitHub Release page has the DMG and `appcast.xml` attached.

## Sidecar binaries (yt-dlp, ffmpeg)

Same seed binaries as the old Tauri build (D12 — bundled as-is, not
rebuilt): `native/project.yml`'s `postbuildScripts` copies
`vendor/binaries/yt-dlp-aarch64-apple-darwin` and
`ffmpeg-x86_64-apple-darwin` into `Contents/Resources/bin/` at build time.
Run `native/scripts/fetch-sidecars.sh` first if `native/vendor/binaries/` is
empty (gitignored, not committed — see that script's own comments) — CI does
not run this automatically, so a release built without it ships without a
working yt-dlp/ffmpeg until `YtdlpUpdater` self-updates yt-dlp on first
launch (ffmpeg has no such self-update path, so CI must have real binaries
checked out for a release to actually work).
