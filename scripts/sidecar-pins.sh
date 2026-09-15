#!/usr/bin/env bash
# Pinned ffmpeg version and checksums, sourced by both fetch-sidecars.sh (which
# downloads and verifies) and release.sh (which refuses to build against a
# binary on disk that doesn't match). One file so the two can't drift apart.
#
# Only variable assignments here — this is sourced, never run.
#
# To bump: set FFMPEG_VERSION, blank both hashes, run scripts/fetch-sidecars.sh;
# it fails and prints the hashes it saw. Check the zip's against
# https://evermeet.cx/ffmpeg/, then paste both in.
FFMPEG_VERSION="9.0.1"
# SHA-256 of https://evermeet.cx/ffmpeg/ffmpeg-$FFMPEG_VERSION.zip
FFMPEG_ZIP_SHA256="8a8c9e549983409fe6604b9aa665648b7a5def9407fe814c39c8b2ea7f64a48f"
# SHA-256 of the `ffmpeg` binary inside that zip — what actually gets bundled,
# and what release.sh checks on disk.
FFMPEG_BINARY_SHA256="e27de05e3a9f9c758f9766d15d1a069fddeed5f725e35d9ab28683be4740dad7"
