# magiclantern_hydrogen — Unified Task Runner
# ===========================================
#
# Single source of truth for build / test / lint / qemu / cache / release
# operations. Mirrors the contract in ../GloriousFlywheel/Justfile and
# ../oauth-mux/Justfile.
#
# Prerequisites:
#   - just (https://github.com/casey/just)
#   - direnv (loads Nix devShell automatically)
#   - Nix with flakes enabled
#
# Quick start:
#   direnv allow
#   just info
#   just build PLATFORM=5D3.123
#
# In-scope platforms (CI matrix):
#   5D2.212  5D3.113  5D3.123  5D4.133

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# Recipes prefixed with `_` are internal helpers.

IN_SCOPE_PLATFORMS := "5D2.212 5D3.113 5D3.123 5D4.133"

# Default recipe — list all commands.
default:
    @just --list --unsorted

# ── Bootstrap ──────────────────────────────────────────────────────────────

# First-time local setup. Idempotent.
setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f .env ] && [ -f .env.example ]; then
      cp .env.example .env
      echo "Created .env from .env.example."
    fi
    pre-commit install --install-hooks 2>/dev/null || true
    echo "Setup complete. Run 'just info' to see toolchain state."

# Show toolchain versions, cache status, in-scope platforms.
info:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "magiclantern_hydrogen — devshell info"
    echo "====================================="
    echo "arm-none-eabi-gcc : $(arm-none-eabi-gcc --version | head -1)"
    echo "zig               : $(zig version)"
    echo "python            : $(python3 --version)"
    echo "lua               : $(lua -v 2>&1 | head -1)"
    echo "qemu-system-arm   : $(qemu-system-arm --version | head -1)"
    echo "bazelisk          : $(bazelisk version 2>/dev/null | head -1 || echo unset)"
    echo "git-cliff         : $(git-cliff --version)"
    echo "just              : $(just --version)"
    echo ""
    echo "In-scope platforms: {{IN_SCOPE_PLATFORMS}}"
    echo "Bazel mode        : ${GF_BAZEL_SUBSTRATE_MODE:-unset}"
    echo "Remote cache      : ${BAZEL_REMOTE_CACHE:-unset}"

# ── Formatting / linting ───────────────────────────────────────────────────

# Format every supported file in the tree.
fmt:
    treefmt

# Check formatting without writing.
fmt-check:
    treefmt --fail-on-change

# Lint touched C and Zig sources.
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    # clang-tidy on touched C files. Compare against origin/dev when
    # running outside a PR; fall back to the working tree if no upstream.
    base="$(git merge-base HEAD origin/dev 2>/dev/null || git rev-parse HEAD)"
    changed_c=$(git diff --name-only "$base" -- '*.c' '*.h' | grep -v '^src/libs/' || true)
    if [ -n "$changed_c" ]; then
      echo "$changed_c" | xargs -r clang-tidy --quiet -- 2>/dev/null || true
    fi
    # Zig modules. Skip cleanly when there are no zig sources yet.
    if ls -d tools/* modules/raw_spectral modules/af_logger 2>/dev/null | xargs -I{} test -f "{}/build.zig" 2>/dev/null; then
      for d in tools/* modules/raw_spectral modules/af_logger; do
        [ -f "$d/build.zig" ] && (cd "$d" && zig build test --summary all)
      done
    fi

# ── Firmware build ─────────────────────────────────────────────────────────

# Build firmware for a single platform.
#   Usage: just build PLATFORM=5D3.123
build PLATFORM:
    make -C platform/{{PLATFORM}}

# Build every in-scope platform sequentially.
build-all:
    #!/usr/bin/env bash
    set -euo pipefail
    for p in {{IN_SCOPE_PLATFORMS}}; do
      echo "── building $p ──"
      make -C "platform/$p"
    done

# Build firmware modules (independent of platform).
build-modules:
    make -C modules

# Clean firmware build artifacts.
clean:
    #!/usr/bin/env bash
    set -euo pipefail
    for p in {{IN_SCOPE_PLATFORMS}}; do
      make -C "platform/$p" clean || true
    done
    make -C modules clean || true

# ── QEMU ───────────────────────────────────────────────────────────────────

# Boot the named platform in qemu-eos and run boot-smoke.
#   Requires ../qemu-eos checked out and built (sibling repo).
#   Stub until A4 wires the qemu-eos build path. See Linear TIN-1217.
qemu-test PLATFORM:
    @echo "qemu-test {{PLATFORM}}: not yet wired. See TIN-1217 (Sprint A4)."
    @exit 1

# Run qemu-test against every in-scope platform.
qemu-matrix:
    @echo "qemu-matrix: not yet wired. See TIN-1217 (Sprint A4)."
    @exit 1

# ── Host-side tests ────────────────────────────────────────────────────────

# Run host-side Bazel + Zig unit tests.
test:
    @echo "test: host-side bazel/zig tests not yet wired. See Sprint A3."
    @exit 1

# Full local CI mirror — run everything CI runs.
ci-local: fmt-check lint build-all
    @echo "ci-local: build-all passed. qemu-matrix + test are stubs (see TIN-1217)."

# ── Flywheel attic cache ───────────────────────────────────────────────────

# Describe the Flywheel attic cache attachment state (descriptive, exit 0
# even in compatibility-local-only mode).
cache-contract:
    bash scripts/cache-attachment-contract.sh

# Verify the Flywheel attic cache attachment contract is satisfied. Exits
# nonzero unless BAZEL_REMOTE_CACHE is set to a real endpoint.
cache-contract-strict:
    bash scripts/cache-attachment-contract.sh --strict

# Verify the strict contract for both Bazel and Nix/Attic attachments.
cache-contract-strict-nix:
    bash scripts/cache-attachment-contract.sh --strict --strict-nix

# Bazel build through the shared cache-backed path.
#   Usage: just bazel-build-cached //path/to:target [extra args...]
bazel-build-cached *ARGS:
    bash scripts/bazel-cache-backed.sh build {{ARGS}}

# Bazel test through the shared cache-backed path.
bazel-test-cached *ARGS:
    bash scripts/bazel-cache-backed.sh test {{ARGS}}

# ── Raw / MLV tooling ──────────────────────────────────────────────────────

# Decode an MLV file to DNG via the calibration-aware host pipeline.
#   Stub until B3 lands tools/raw-stack. See TIN issues in Project B.
mlv-decode FILE:
    @echo "mlv-decode {{FILE}}: tools/raw-stack not yet implemented (Sprint B3)."
    @exit 1

# ── AF logger tooling ──────────────────────────────────────────────────────

# Replay an AFLG capture as an annotated timeline.
#   Stub until C4 lands tools/af-log. See TIN issues in Project C.
af-log-replay FILE:
    @echo "af-log-replay {{FILE}}: tools/af-log not yet implemented (Sprint C4)."
    @exit 1

# ── Changelog / release ────────────────────────────────────────────────────

# Regenerate CHANGELOG.md from conventional commits.
changelog:
    git-cliff -o CHANGELOG.md

# Tag a release, regenerate CHANGELOG, push.
#   Usage: just release v0.1.0
release VERSION:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! [[ "{{VERSION}}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
      echo "VERSION must look like vMAJOR.MINOR.PATCH (got '{{VERSION}}')"
      exit 2
    fi
    git-cliff --tag "{{VERSION}}" -o CHANGELOG.md
    git add CHANGELOG.md
    git commit -m "chore(release): {{VERSION}}"
    git tag -a "{{VERSION}}" -m "Release {{VERSION}}"
    git push --follow-tags
