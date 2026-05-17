#!/usr/bin/env bash
# Compose per-platform firmware tarballs for a magiclantern_hydrogen release.
#
# Reads env: TAG. Expects firmware artifacts at ./firmware-<PLATFORM>/ (as
# downloaded by actions/download-artifact in the publish workflow).
#
# Writes: release-artifacts/magiclantern-hydrogen-<TAG>-<PLATFORM>.tar.gz
#         release-artifacts/magiclantern-hydrogen-<TAG>-<PLATFORM>.tar.gz.sha256
#
# Tarball layout:
#   magiclantern-hydrogen-<TAG>-<PLATFORM>/
#   ├── autoexec.bin        (firmware entry)
#   ├── ML-SETUP.FIR        (firmware installer)
#   ├── modules/            (built .mo files)
#   ├── MODULES.txt         (manifest of module names)
#   ├── INSTALL.md          (canonical install / recovery / uninstall guide)
#   └── README.md           (per-platform notes)

set -euo pipefail

: "${TAG:?TAG is required}"

PLATFORMS=(5D2.212 5D3.113 5D3.123 5D4.133)
mkdir -p release-artifacts

for P in "${PLATFORMS[@]}"; do
  STAGE="magiclantern-hydrogen-${TAG}-${P}"
  echo "==> Composing ${STAGE}"
  rm -rf "$STAGE"
  mkdir -p "$STAGE/modules"

  SRC="firmware-${P}"
  if [ ! -d "$SRC" ]; then
    echo "compose-firmware-tarballs.sh: WARN '$SRC' not present; skipping ${P}" >&2
    continue
  fi

  # Firmware entry + installer (best-effort find since the build outputs them
  # under platform/<P>/ or platform/<P>/build/<P>/).
  find "$SRC" -name 'autoexec.bin'  -print -quit | xargs -I{} cp {} "$STAGE/" || true
  find "$SRC" -name 'ML-SETUP.FIR'  -print -quit | xargs -I{} cp {} "$STAGE/" || true

  # All built modules (.mo).
  while IFS= read -r -d '' mo; do
    cp "$mo" "$STAGE/modules/"
  done < <(find "$SRC" -name '*.mo' -print0 2>/dev/null)

  # Manifest of module names; empty if nothing built.
  ( cd "$STAGE/modules" && ls -1 *.mo 2>/dev/null || true ) > "$STAGE/MODULES.txt"

  # Canonical install doc + per-platform README.
  if [ -f docs/INSTALL.md ]; then cp docs/INSTALL.md "$STAGE/INSTALL.md"; fi
  if [ -f "docs/platform-notes/${P}.md" ]; then
    cp "docs/platform-notes/${P}.md" "$STAGE/README.md"
  fi

  # Tarball + SHA256 sidecar.
  tar czf "release-artifacts/${STAGE}.tar.gz" "$STAGE"
  ( cd release-artifacts && shasum -a 256 "${STAGE}.tar.gz" > "${STAGE}.tar.gz.sha256" )
  rm -rf "$STAGE"
  echo "    wrote release-artifacts/${STAGE}.tar.gz"
done

echo
echo "compose-firmware-tarballs.sh done. Contents:"
ls -la release-artifacts/ | grep -E 'magiclantern-hydrogen.*tar\.gz' || true
