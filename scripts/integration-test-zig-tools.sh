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

echo "==> raw-stack stack on fixture (RAWX aggregate):"
STACK_OUT="$("$RAW_STACK" stack "$FIXTURE")"
echo "$STACK_OUT"
if ! echo "$STACK_OUT" | grep -q "DIGITAL_GAIN     yes"; then
  echo "FAIL: expected stack output to report DIGITAL_GAIN=yes" >&2
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
