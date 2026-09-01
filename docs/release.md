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

**Sparkle EdDSA keypair** — not generated yet. Grab the tools from a
Sparkle release tarball (version must match `project.yml`'s pinned SPM
version) and run:
```bash
curl -fsSL -o /tmp/sparkle.tar.xz \
  https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz
mkdir -p /tmp/sparkle-tools && tar -xf /tmp/sparkle.tar.xz -C /tmp/sparkle-tools
/tmp/sparkle-tools/bin/generate_keys --account dkb-downloader
```
The `--account dkb-downloader` flag is **required** — omitting it falls
back to the Keychain's default `ed25519` account, which is already
occupied by DKB Monitor's key (Sparkle's own docs: "you only need one
signing key, no matter how many apps you embed Sparkle in" — true in
general, but this repo deliberately keeps a separate key per app for
isolation). Paste the printed public key into `SUPublicEDKey` in
`project.yml` (currently the placeholder
`REPLACE_WITH_GENERATED_ED25519_PUBLIC_KEY`).

Once that's done and a first version has been uploaded (see below), flip
`SUEnableAutomaticChecks` to `true` in `project.yml` — it's `false` until
then, otherwise Sparkle pops an "Unable to Check for Updates" alert on
every launch since there's no feed to reach yet.

## Cutting a release

```bash
./scripts/release.sh
```

Fetches sidecar binaries if missing. Prompts for the version as
`MAJOR.MINOR.BUILD` (e.g. `2.0.1` → marketing version `2.0`, build `1`;
Enter keeps both as they are), writes it into `project.yml` (the actual
source of truth — editing `Info.plist` directly gets silently discarded by
the next `xcodegen generate`), then runs: `swift test` → `xcodegen
generate` → ad-hoc-signed Release build → DMG → Sparkle-sign (under the
`dkb-downloader` account). Output lands in `release-output/<version>/`
(gitignored): the `.dmg` and its `.sig` (the raw EdDSA signature, ready to
paste as-is).

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
