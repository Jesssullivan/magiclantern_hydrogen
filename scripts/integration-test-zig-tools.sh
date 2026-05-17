#!/usr/bin/env bash
# Integration test for tools/raw-stack and tools/af-log.
#
# 1. Build both binaries.
# 2. Use `raw-stack fixture` to write a synthetic MLV with RAWX + AFLG
#    blocks (no firmware needed).
# 3. `raw-stack inspect` and assert it sees the expected RAWX + AFLG
#    counts.
# 4. `af-log replay` and `af-log summary` and assert counts.
#
# Runs in nix shell with nixpkgs#zig available. Used by
# .github/workflows/ci.yml to catch regressions in the block layout
# without needing the firmware loop.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "==> Building raw-stack"
(cd "$ROOT/tools/raw-stack" && zig build)
RAW_STACK="$ROOT/tools/raw-stack/zig-out/bin/raw-stack"

echo "==> Building af-log"
(cd "$ROOT/tools/af-log" && zig build)
AF_LOG="$ROOT/tools/af-log/zig-out/bin/af-log"

FIXTURE="$WORKDIR/synthetic.mlv"
echo "==> Generating fixture at $FIXTURE"
"$RAW_STACK" fixture "$FIXTURE"
ls -la "$FIXTURE"

INSPECT_OUT="$("$RAW_STACK" inspect "$FIXTURE")"
echo "==> raw-stack inspect output:"
echo "$INSPECT_OUT"

RAWX_COUNT=$(echo "$INSPECT_OUT" | grep -c '^RAWX ' || true)
AFLG_COUNT=$(echo "$INSPECT_OUT" | grep -c '^AFLG ' || true)
echo "RAWX rows: $RAWX_COUNT  (expected 4)"
echo "AFLG rows: $AFLG_COUNT  (expected 6)"

if [[ $RAWX_COUNT -ne 4 ]]; then
  echo "FAIL: expected 4 RAWX rows in inspect output, got $RAWX_COUNT" >&2
  exit 1
fi
if [[ $AFLG_COUNT -ne 6 ]]; then
  echo "FAIL: expected 6 AFLG rows in inspect output, got $AFLG_COUNT" >&2
  exit 1
fi

echo "==> af-log replay output:"
REPLAY_OUT="$("$AF_LOG" replay "$FIXTURE")"
echo "$REPLAY_OUT"
REPLAY_EVENTS=$(echo "$REPLAY_OUT" | tail -n +3 | grep -cv '^$' || true)
echo "af-log replay events (excluding header): $REPLAY_EVENTS  (expected 6)"
if [[ $REPLAY_EVENTS -ne 6 ]]; then
  echo "FAIL: expected 6 AFLG events from af-log replay, got $REPLAY_EVENTS" >&2
  exit 1
fi

echo "==> af-log summary output:"
SUMMARY_OUT="$("$AF_LOG" summary "$FIXTURE")"
echo "$SUMMARY_OUT"
if ! echo "$SUMMARY_OUT" | grep -q "6 AFLG blocks total"; then
  echo "FAIL: summary should report '6 AFLG blocks total'" >&2
  exit 1
fi

echo "==> raw-stack info on fixture:"
INFO_OUT="$("$RAW_STACK" info "$FIXTURE")"
echo "$INFO_OUT"
if ! echo "$INFO_OUT" | grep -q "RAWI: 8x8"; then
  echo "FAIL: expected RAWI: 8x8 in info output (fixture geometry)" >&2
  exit 1
fi
if ! echo "$INFO_OUT" | grep -q "14-bit"; then
  echo "FAIL: expected 14-bit in info output" >&2
  exit 1
fi

echo "==> raw-stack frames on fixture:"
FRAMES_OUT="$("$RAW_STACK" frames "$FIXTURE")"
echo "$FRAMES_OUT"
if ! echo "$FRAMES_OUT" | grep -q "4 VIDF blocks total"; then
  echo "FAIL: expected 4 VIDF blocks from raw-stack frames" >&2
  exit 1
fi

echo "==> raw-stack raw-stats on fixture:"
RAWSTATS_OUT="$("$RAW_STACK" raw-stats "$FIXTURE")"
echo "$RAWSTATS_OUT"
if ! echo "$RAWSTATS_OUT" | grep -q "4 VIDF blocks"; then
  echo "FAIL: expected 4 VIDF blocks in raw-stats output" >&2
  exit 1
fi
# Fixture writes 112 bytes per VIDF (frame_number + i mod 256). Total
# = 4 frames x 112 = 448 bytes.
if ! echo "$RAWSTATS_OUT" | grep -qE "448 total payload bytes"; then
  echo "FAIL: expected 448 total payload bytes (4 frames x 112 bytes each)" >&2
  exit 1
fi

echo "==> raw-stack mean-frame on fixture (raw u16 LE):"
MEAN_OUT="$WORKDIR/mean.bin"
MEAN_LOG="$("$RAW_STACK" mean-frame "$FIXTURE" "$MEAN_OUT")"
echo "$MEAN_LOG"
if ! echo "$MEAN_LOG" | grep -qE "stacked 4 VIDF frames -> 64 pixels"; then
  echo "FAIL: expected 'stacked 4 VIDF frames -> 64 pixels' in mean-frame output" >&2
  exit 1
fi
mean_size=$(/usr/bin/stat -c %s "$MEAN_OUT" 2>/dev/null || /usr/bin/stat -f %z "$MEAN_OUT")
if [[ "$mean_size" -ne 128 ]]; then
  echo "FAIL: expected raw mean-frame output to be 128 bytes (64 pixels * 2), got $mean_size" >&2
  exit 1
fi

echo "==> raw-stack mean-frame on fixture (FITS):"
FITS_OUT="$WORKDIR/mean.fits"
FITS_LOG="$("$RAW_STACK" mean-frame "$FIXTURE" "$FITS_OUT")"
echo "$FITS_LOG"
fits_size=$(/usr/bin/stat -c %s "$FITS_OUT" 2>/dev/null || /usr/bin/stat -f %z "$FITS_OUT")
# 2880 (header) + ceil(128/2880)*2880 = 2880 + 2880 = 5760 bytes.
if [[ "$fits_size" -ne 5760 ]]; then
  echo "FAIL: expected FITS output to be 5760 bytes, got $fits_size" >&2
  exit 1
fi
# Sanity: FITS header magic.
if ! /usr/bin/head -c 9 "$FITS_OUT" | grep -q "SIMPLE  ="; then
  echo "FAIL: FITS output does not start with 'SIMPLE  =' header keyword" >&2
  /usr/bin/head -c 80 "$FITS_OUT" | /usr/bin/od -c | /usr/bin/head -3 >&2
  exit 1
fi

echo "==> raw-stack median-frame on fixture:"
MEDIAN_OUT="$WORKDIR/median.bin"
MEDIAN_LOG="$("$RAW_STACK" median-frame "$FIXTURE" "$MEDIAN_OUT")"
echo "$MEDIAN_LOG"
if ! echo "$MEDIAN_LOG" | grep -qE "stacked 4 samples-per-pixel across 64 pixels"; then
  echo "FAIL: expected '4 samples-per-pixel across 64 pixels' in median-frame output" >&2
  exit 1
fi
median_size=$(/usr/bin/stat -c %s "$MEDIAN_OUT" 2>/dev/null || /usr/bin/stat -f %z "$MEDIAN_OUT")
if [[ "$median_size" -ne 128 ]]; then
  echo "FAIL: expected median-frame raw output to be 128 bytes, got $median_size" >&2
  exit 1
fi

echo "==> raw-stack bayer-stats on fixture:"
BAYER_OUT="$("$RAW_STACK" bayer-stats "$FIXTURE")"
echo "$BAYER_OUT"
# 4 frames x 64 pixels = 256 total. Split RGGB: 64 per plane.
for plane in "R " "G1" "G2" "B "; do
  if ! echo "$BAYER_OUT" | grep -qE "${plane}.*count=64"; then
    echo "FAIL: expected ${plane} count=64 in bayer-stats output" >&2
    exit 1
  fi
done

echo "==> raw-stack pixel-stats on fixture:"
PIXSTATS_OUT="$("$RAW_STACK" pixel-stats "$FIXTURE")"
echo "$PIXSTATS_OUT"
# 4 frames x (112 bytes / 14 bytes-per-block) x 8 pixels-per-block = 256 pixels.
if ! echo "$PIXSTATS_OUT" | grep -qE "256 total pixels"; then
  echo "FAIL: expected 256 total pixels in pixel-stats output" >&2
  exit 1
fi

echo "==> raw-stack stack on fixture (RAWX aggregate):"
STACK_OUT="$("$RAW_STACK" stack "$FIXTURE")"
echo "$STACK_OUT"
if ! echo "$STACK_OUT" | grep -q "DIGITAL_GAIN     yes"; then
  echo "FAIL: expected stack output to report DIGITAL_GAIN=yes" >&2
  exit 1
fi

echo "==> raw-stack dark-subtract on fixture (using mean-frame as master dark):"
DARK_OUT="$WORKDIR/dark_subtracted.bin"
DARK_LOG="$("$RAW_STACK" dark-subtract "$MEAN_OUT" "$FIXTURE" "$DARK_OUT")"
echo "$DARK_LOG"
if ! echo "$DARK_LOG" | grep -qE "stacked 4 VIDF frames -> 64 pixels"; then
  echo "FAIL: expected 'stacked 4 VIDF frames -> 64 pixels' in dark-subtract output" >&2
  exit 1
fi
dark_size=$(/usr/bin/stat -c %s "$DARK_OUT" 2>/dev/null || /usr/bin/stat -f %z "$DARK_OUT")
if [[ "$dark_size" -ne 128 ]]; then
  echo "FAIL: expected dark-subtract output to be 128 bytes, got $dark_size" >&2
  exit 1
fi

echo "==> raw-stack dark-subtract on fixture (FITS output):"
DARK_FITS="$WORKDIR/dark_subtracted.fits"
"$RAW_STACK" dark-subtract "$MEAN_OUT" "$FIXTURE" "$DARK_FITS" >/dev/null
darkfits_size=$(/usr/bin/stat -c %s "$DARK_FITS" 2>/dev/null || /usr/bin/stat -f %z "$DARK_FITS")
if [[ "$darkfits_size" -ne 5760 ]]; then
  echo "FAIL: expected dark-subtract FITS output to be 5760 bytes, got $darkfits_size" >&2
  exit 1
fi

echo "==> raw-stack sigma-stack on fixture (defaults):"
SIGMA_OUT="$WORKDIR/sigma.bin"
SIGMA_LOG="$("$RAW_STACK" sigma-stack "$FIXTURE" "$SIGMA_OUT")"
echo "$SIGMA_LOG"
if ! echo "$SIGMA_LOG" | grep -qE "sigma=3\.00 iters=2 samples-per-pixel=4 pixels=64"; then
  echo "FAIL: expected default sigma=3.00 iters=2 samples-per-pixel=4 pixels=64" >&2
  exit 1
fi
sigma_size=$(/usr/bin/stat -c %s "$SIGMA_OUT" 2>/dev/null || /usr/bin/stat -f %z "$SIGMA_OUT")
if [[ "$sigma_size" -ne 128 ]]; then
  echo "FAIL: expected sigma-stack output to be 128 bytes, got $sigma_size" >&2
  exit 1
fi

echo "==> raw-stack sigma-stack with --sigma 1.5 --iters 3:"
SIGMA_OUT2="$WORKDIR/sigma_tight.bin"
SIGMA_LOG2="$("$RAW_STACK" sigma-stack --sigma 1.5 --iters 3 "$FIXTURE" "$SIGMA_OUT2")"
echo "$SIGMA_LOG2"
if ! echo "$SIGMA_LOG2" | grep -qE "sigma=1\.50 iters=3"; then
  echo "FAIL: expected sigma=1.50 iters=3 in custom sigma-stack output" >&2
  exit 1
fi

COMPLEX="$WORKDIR/complex.mlv"
echo "==> Generating complex fixture at $COMPLEX"
"$RAW_STACK" fixture "$COMPLEX" complex

echo "==> af-log detect on complex fixture:"
DETECT_OUT="$("$AF_LOG" detect "$COMPLEX")"
echo "$DETECT_OUT"
for pattern in focus_bracket tracking_dwell hunting; do
  if ! echo "$DETECT_OUT" | grep -q "^$pattern "; then
    echo "FAIL: expected af-log detect to find '$pattern' in complex fixture" >&2
    exit 1
  fi
done

echo
echo "OK: round-trip fixture -> raw-stack inspect -> af-log replay/summary/detect"
