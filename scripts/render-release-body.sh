#!/usr/bin/env bash
# Render the rich GitHub release body for magiclantern_hydrogen.
#
# Reads env: TAG, PREV_TAG, GITHUB_REPOSITORY, KIND (semver|nightly).
# Writes: RELEASE_NOTES.md in CWD.
#
# Assumes the publish job has staged tarballs under release-artifacts/ but
# does not consult that directory — links are derived from TAG + a fixed
# matrix. Missing tarballs on the resulting release will 404 in their link,
# which is intentional: the link is the canonical name we agreed to ship,
# not a probe of what actually built.

set -euo pipefail

: "${TAG:?TAG is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
KIND="${KIND:-semver}"
PREV_TAG="${PREV_TAG:-}"

BASE_URL="https://github.com/${GITHUB_REPOSITORY}/releases/download/${TAG}"
TREE_URL="https://github.com/${GITHUB_REPOSITORY}/blob/${TAG}"

case "$KIND" in
  nightly)
    KIND_BANNER=$'> [!WARNING]\n> **Nightly build** — not for production use. Built from `dev` HEAD; auto-pruned after 7 nightlies.\n'
    ;;
  semver)
    KIND_BANNER=""
    ;;
  *)
    echo "render-release-body.sh: unknown KIND='$KIND'" >&2
    exit 2
    ;;
esac

cat > RELEASE_NOTES.md <<EOF
# magiclantern_hydrogen ${TAG}

${KIND_BANNER}

Research fork of Magic Lantern for spectral / astro imaging on
heavily-modified Canon DSLRs. Each release bundles per-camera firmware
plus host-side raw / AF tooling.

## Install firmware

Pick the tarball matching your camera + firmware version, extract to your
SD card root, then boot the camera with the card inserted.

| Camera | Firmware | Download | SHA256 |
|---|---|---|---|
| Canon 5D Mark II | 2.1.2 | [tarball](${BASE_URL}/magiclantern-hydrogen-${TAG}-5D2.212.tar.gz) | [.sha256](${BASE_URL}/magiclantern-hydrogen-${TAG}-5D2.212.tar.gz.sha256) |
| Canon 5D Mark III | 1.1.3 | [tarball](${BASE_URL}/magiclantern-hydrogen-${TAG}-5D3.113.tar.gz) | [.sha256](${BASE_URL}/magiclantern-hydrogen-${TAG}-5D3.113.tar.gz.sha256) |
| Canon 5D Mark III | 1.2.3 | [tarball](${BASE_URL}/magiclantern-hydrogen-${TAG}-5D3.123.tar.gz) | [.sha256](${BASE_URL}/magiclantern-hydrogen-${TAG}-5D3.123.tar.gz.sha256) |
| Canon 5D Mark IV | 1.3.3 | [tarball](${BASE_URL}/magiclantern-hydrogen-${TAG}-5D4.133.tar.gz) | [.sha256](${BASE_URL}/magiclantern-hydrogen-${TAG}-5D4.133.tar.gz.sha256) |

\`\`\`bash
# Replace 5D3.123 with the platform matching your camera.
PLATFORM=5D3.123
curl -L ${BASE_URL}/magiclantern-hydrogen-${TAG}-\${PLATFORM}.tar.gz | tar xz
# Mount the SD card (macOS shown; Linux uses /run/media/\$USER/EOS_DIGITAL).
cp -r magiclantern-hydrogen-${TAG}-\${PLATFORM}/* /Volumes/EOS_DIGITAL/
diskutil unmount /Volumes/EOS_DIGITAL
\`\`\`

Full install procedure, recovery, and uninstall: [INSTALL.md](${TREE_URL}/docs/INSTALL.md).

## Host tools

Multi-camera workflows for spectral / astro reduction and AF / lens
telemetry analysis. Static musl on Linux; native dylib on macOS.

| Tool | Linux x86_64 | macOS aarch64 | What it does |
|---|---|---|---|
| **raw-stack** | [tarball](${BASE_URL}/raw-stack-${TAG}-x86_64-linux.tar.gz) | [tarball](${BASE_URL}/raw-stack-${TAG}-aarch64-macos.tar.gz) | RAWI/VIDF decode, RGGB bayer stats, mean / median / sigma-clipped stacking, master-dark subtract, FITS writer |
| **af-log** | [tarball](${BASE_URL}/af-log-${TAG}-x86_64-linux.tar.gz) | [tarball](${BASE_URL}/af-log-${TAG}-aarch64-macos.tar.gz) | AFLG replay, summary, classifier-based pattern detection (focus_bracket / tracking_dwell / hunting) |

\`\`\`bash
curl -L ${BASE_URL}/raw-stack-${TAG}-x86_64-linux.tar.gz | tar xz
./raw-stack-${TAG}-x86_64-linux/raw-stack info my-capture.mlv
./raw-stack-${TAG}-x86_64-linux/raw-stack sigma-stack --sigma 3.0 darks/*.mlv master-dark.bin
./raw-stack-${TAG}-x86_64-linux/raw-stack dark-subtract master-dark.bin lights/*.mlv reduced.fits
\`\`\`

Full reference (every subcommand + flag + example): [USAGE.md](${TREE_URL}/docs/USAGE.md).

## Verification

Every tarball ships with a SHA256 sidecar:

\`\`\`bash
curl -LO ${BASE_URL}/magiclantern-hydrogen-${TAG}-5D3.123.tar.gz
curl -LO ${BASE_URL}/magiclantern-hydrogen-${TAG}-5D3.123.tar.gz.sha256
sha256sum -c magiclantern-hydrogen-${TAG}-5D3.123.tar.gz.sha256
\`\`\`

EOF

if [ -n "$PREV_TAG" ]; then
  cat >> RELEASE_NOTES.md <<EOF
## Changes since ${PREV_TAG}

**Full diff:** [${PREV_TAG}…${TAG}](https://github.com/${GITHUB_REPOSITORY}/compare/${PREV_TAG}...${TAG}).

EOF
else
  echo "## Changelog" >> RELEASE_NOTES.md
  echo >> RELEASE_NOTES.md
fi

# Append cliff-rendered changelog. --latest scopes to the most recent tag's
# commits; --strip header drops the duplicate "# Changelog" preamble.
if command -v git-cliff >/dev/null 2>&1; then
  git-cliff --latest --strip header >> RELEASE_NOTES.md
else
  echo "_git-cliff not on PATH; changelog skipped._" >> RELEASE_NOTES.md
fi

echo "render-release-body.sh: wrote RELEASE_NOTES.md ($(wc -c < RELEASE_NOTES.md) bytes)"
