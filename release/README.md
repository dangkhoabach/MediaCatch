# Releasing DKB Downloader (macOS + Windows)

```bash
release/release.sh
```

Shows the current version and asks which version to release (Enter keeps it
unchanged — no auto-bump), then builds + signs the macOS release into
`release/output/<version>/macos/`. Windows is a separate step on a separate
machine (see below) — there's no way around that, see "Why Windows is
separate" below.

**Current status: macOS build is unsigned (no Apple Developer ID certificate
installed yet)** — Gatekeeper will warn on first launch, right-click > Open
bypasses it. Once a Developer ID Application certificate is imported into
Keychain on this machine, `npm run tauri build` will pick it up automatically
for codesigning; notarization needs `APPLE_ID`, `APPLE_PASSWORD` (an
app-specific password), and `APPLE_TEAM_ID` env vars added to
`.env.release` alongside the updater signing key already there.

## Sidecar binaries (yt-dlp, ffmpeg)

Run once before building (or whenever you want to refresh the seed
versions):

```bash
scripts/fetch-sidecars.sh
```

Fetches macOS binaries only (universal yt-dlp + x86_64 ffmpeg — see
`THIRD-PARTY-NOTICES.md` for why ffmpeg is x86_64-only and its GPL license).
**Windows sidecar binaries are not automated yet** — before
`build-windows.ps1` can succeed, `src-tauri/binaries/` needs:
- `yt-dlp-x86_64-pc-windows-msvc.exe` — download `yt-dlp.exe` from
  https://github.com/yt-dlp/yt-dlp/releases/latest and rename.
- `ffmpeg-x86_64-pc-windows-msvc.exe` — download a static Windows build (e.g.
  from https://www.gyan.dev/ffmpeg/builds/, the "essentials" or "full"
  release build's `bin/ffmpeg.exe`) and rename.

## Uploading a build

Not automated — go to **admin.dangkhoabach.vn → Apps** and use "Publish new
app" (first release) or "Republish" (existing app), ticking the platform row
you just built and uploading its 3 files:

| Form field | macOS | Windows |
|---|---|---|
| Installer file | `DKB.Downloader_<version>_aarch64.dmg` | `*-setup.exe` (or `.msi`) |
| Updater bundle | `DKB.Downloader_aarch64.app.tar.gz` | `*.nsis.zip` (or `.msi.zip`) |
| Signature (.sig) | `DKB.Downloader_aarch64.app.tar.gz.sig` | matching `.sig` |

The admin panel builds `app.json`/`latest.json` itself from whatever you
upload — these scripts don't touch either file. **A "dkb-downloader" app
entry needs to exist in that admin panel first** (separate from
"dkb-monitor") — this is a manual one-time setup step outside this repo.

## Windows: build on an actual Windows machine

```powershell
git pull
powershell -ExecutionPolicy Bypass -File release\build-windows.ps1
```

Produces `release/output/<version>/windows/`.

### Why Windows is separate — can't build it from this Mac

Cross-compiling fails even at `cargo check`: the `ring` crate (a dependency
of the updater's TLS stack) needs a real Windows C toolchain to compile, and
the NSIS/MSI installer bundlers only run on Windows (verified the same way
for DKB-Monitor, same dependency stack here). There's no CI here either
(kept deliberately simple, per-machine scripts only) — a real Windows box is
required.

**Important ordering:** `build-windows.ps1` builds whatever version is
currently checked out — so commit + push the version bump from the macOS
side *before* pulling on Windows, or the two platforms will end up at
different versions:

```bash
git diff                                  # review the version bump
git add -A && git commit -m "..."         # Release keyword, per git-rule.md
git push
```

### One-time Windows machine setup

- Node.js, Rust (`rustup`), Visual Studio Build Tools (C++ workload) — same
  as any Tauri Windows dev environment.
- The two Windows sidecar `.exe` files (see "Sidecar binaries" above).
- Copy the signing private key (`~/.tauri/dkb-downloader-updater.key` on
  this Mac) onto the Windows machine, and create `.env.release` at the repo
  root there (same format and location as the macOS one — both scripts read
  `<repo root>/.env.release`, not `release/.env.release` — gitignored, never
  commit it):
  ```
  TAURI_SIGNING_PRIVATE_KEY=C:\path\to\dkb-downloader-updater.key
  TAURI_SIGNING_PRIVATE_KEY_PASSWORD=<same password as the macOS .env.release>
  ```
  Same keypair as macOS — required, since both platforms' builds are
  verified by the one public key already embedded in `tauri.conf.json`.

> **Not verified end-to-end** — `build-windows.ps1` was written and reviewed
> carefully but never actually run (no Windows machine available in the
> environment that wrote it). Sanity-check the first real run, especially
> the installer/updater filename globs if Tauri's actual output under
> `src-tauri/target/release/bundle/` differs from what's assumed
> (`nsis/*-setup.exe` + `*.nsis.zip`, falling back to `msi/*.msi` +
> `*.msi.zip`).

## Files in this folder

- `release.sh` — orchestrator: prompts for the version (Enter keeps the current one, no auto-bump) + macOS build + next-step instructions.
- `set-version.sh <version>` — sets an exact version across `package.json` / `Cargo.toml` / `tauri.conf.json` in lockstep (no bump math).
- `build-macos.sh` — builds (currently unsigned re: Apple codesigning) locally, output to `release/output/<version>/macos/`.
- `build-windows.ps1` — same, for Windows; run on an actual Windows machine after `git pull`.
