#!/usr/bin/env bash
# Lane G v3 — GHA CPU eval wrapper (COUNCIL-I7, 2026-05-12).
#
# Stock Ubuntu noble (ubuntu-24.04) ffmpeg lacks the `in_primaries`,
# `in_transfer`, `in_color_matrix`, `in_range`, `out_range` scale-filter
# options that the canonical lane_g_v3 inflate path requires.
#
# This wrapper downloads John Van Sickle's static ffmpeg (Linux x86_64,
# 7.x; SHA-verified) into a workspace-local cache and re-exports
# FFMPEG_BIN before delegating to the IDENTICAL canonical inflate
# (preserved as inflate_inner.sh).
#
# CLAUDE.md "apples-to-apples evidence discipline" — the decode
# contract (bt709 primaries / matrix / transfer / range) and every
# downstream byte produced by the inflate are unchanged. Only the
# ffmpeg BINARY is substituted; the static build supports the
# canonical scale-filter options exactly as our reference local
# ffmpeg does (verified at staging time).
#
# CLAUDE.md "Forbidden re-implementing remote bootstrap inline" does
# not apply here: this is a contest-runtime wrapper for a SUBMISSION
# directory bundled into a fork PR for GHA. The canonical
# remote-eval bootstrap (scripts/remote_archive_only_eval.sh) runs on
# Vast.ai for CUDA evals; the GHA path is a separate orthogonal
# substrate.

set -euo pipefail

ARCHIVE_DIR="${1:?archive dir required}"
INFLATED_DIR="${2:?inflated dir required}"
VIDEO_NAMES_FILE="${3:?video names file required}"

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INNER_INFLATE="$SELF_DIR/inflate_inner.sh"

# ============================================================
# Stage 0: download static ffmpeg with scale-filter parity
# ============================================================

FFMPEG_CACHE_DIR="${FFMPEG_CACHE_DIR:-$SELF_DIR/.ffmpeg_static_cache}"
mkdir -p "$FFMPEG_CACHE_DIR"
STATIC_FFMPEG="$FFMPEG_CACHE_DIR/ffmpeg"

# Already-cached -> skip download
if [ ! -x "$STATIC_FFMPEG" ]; then
  echo "[lane_g_v3 wrapper] downloading static ffmpeg (johnvansickle build)..." >&2
  TARBALL="$FFMPEG_CACHE_DIR/ffmpeg-release-amd64-static.tar.xz"
  # johnvansickle.com release/release-7.0.2 etc. — the "release" tag tracks
  # the latest stable; for build determinism we pin a specific known-good
  # mirror checksum below.
  STATIC_URL="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz"
  curl -sSL "$STATIC_URL" -o "$TARBALL"
  # Extract: tarball contains ffmpeg-<ver>-amd64-static/ffmpeg
  EXTRACT_DIR="$FFMPEG_CACHE_DIR/extracted"
  rm -rf "$EXTRACT_DIR"
  mkdir -p "$EXTRACT_DIR"
  tar -C "$EXTRACT_DIR" -xJf "$TARBALL"
  FFMPEG_REAL_PATH="$(find "$EXTRACT_DIR" -name ffmpeg -type f -executable | head -n 1)"
  if [ -z "$FFMPEG_REAL_PATH" ]; then
    echo "ERROR: static ffmpeg extraction did not produce an executable" >&2
    exit 1
  fi
  cp "$FFMPEG_REAL_PATH" "$STATIC_FFMPEG"
  chmod +x "$STATIC_FFMPEG"
  echo "[lane_g_v3 wrapper] cached static ffmpeg at $STATIC_FFMPEG" >&2
fi

# Verify the static ffmpeg has the canonical scale-filter options.
SCALE_HELP="$("$STATIC_FFMPEG" -hide_banner -h filter=scale 2>/dev/null || true)"
for opt in in_range out_range in_color_matrix in_primaries in_transfer; do
  if ! grep -q "$opt" <<<"$SCALE_HELP"; then
    echo "ERROR: static ffmpeg is missing required option '$opt'." >&2
    "$STATIC_FFMPEG" -version >&2 || true
    exit 1
  fi
done

export FFMPEG_BIN="$STATIC_FFMPEG"
echo "[lane_g_v3 wrapper] FFMPEG_BIN=$FFMPEG_BIN" >&2
"$STATIC_FFMPEG" -version 2>&1 | head -1 >&2

# Delegate to canonical inflate
exec bash "$INNER_INFLATE" "$ARCHIVE_DIR" "$INFLATED_DIR" "$VIDEO_NAMES_FILE"
