#!/usr/bin/env bash
# Compose per-(tool x platform) tarballs for a magiclantern_hydrogen release.
#
# Reads env: TAG. Expects tool artifacts at ./<tool>-<suffix>/<tool> as
# downloaded by actions/download-artifact in the publish workflow.
#
# Writes: release-artifacts/<tool>-<TAG>-<suffix>.tar.gz
#         release-artifacts/<tool>-<TAG>-<suffix>.tar.gz.sha256
#
# Tarball layout:
#   <tool>-<TAG>-<suffix>/
#   ├── <tool>              (executable)
#   ├── README.md           (per-tool README)
#   ├── USAGE.md            (man-style usage reference)
#   └── LICENSE

set -euo pipefail

: "${TAG:?TAG is required}"

TOOLS=(raw-stack af-log)
SUFFIXES=(x86_64-linux aarch64-macos)
mkdir -p release-artifacts

for T in "${TOOLS[@]}"; do
  for S in "${SUFFIXES[@]}"; do
    STAGE="${T}-${TAG}-${S}"
    SRC="${T}-${S}"
    echo "==> Composing ${STAGE}"

    if [ ! -d "$SRC" ]; then
      echo "compose-tool-tarballs.sh: WARN '$SRC' not present; skipping" >&2
      continue
    fi

    rm -rf "$STAGE"
    mkdir -p "$STAGE"

    if [ -f "$SRC/${T}" ]; then
      cp "$SRC/${T}" "$STAGE/${T}"
      chmod +x "$STAGE/${T}"
    else
      echo "compose-tool-tarballs.sh: WARN '$SRC/${T}' missing; skipping" >&2
      rm -rf "$STAGE"
      continue
    fi

    # Per-tool docs ship from the source tree (canonical), not from CI.
    if [ -f "tools/${T}/README.md" ]; then cp "tools/${T}/README.md" "$STAGE/"; fi
    if [ -f "tools/${T}/USAGE.md" ];  then cp "tools/${T}/USAGE.md"  "$STAGE/"; fi
    if [ -f LICENSE ]; then cp LICENSE "$STAGE/"; fi

    tar czf "release-artifacts/${STAGE}.tar.gz" "$STAGE"
    ( cd release-artifacts && shasum -a 256 "${STAGE}.tar.gz" > "${STAGE}.tar.gz.sha256" )
    rm -rf "$STAGE"
    echo "    wrote release-artifacts/${STAGE}.tar.gz"
  done
done

echo
echo "compose-tool-tarballs.sh done. Contents:"
ls -la release-artifacts/ | grep -E '(raw-stack|af-log).*tar\.gz' || true
