#!/usr/bin/env bash
# Bazel sh_test entry — chdir into the workspace and invoke zig build test.
#
# Bazel runs sh_test under a stripped env (`exec env -`). Zig needs
# ZIG_GLOBAL_CACHE_DIR (or HOME / XDG_CACHE_HOME) to write its cache, so
# we point it at a workspace-local dir.

set -euo pipefail

# BUILD_WORKSPACE_DIRECTORY is set by `bazel test`; fall back to PWD for
# manual invocation.
cd "${BUILD_WORKSPACE_DIRECTORY:-$PWD}"

export ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-cache-global"
mkdir -p "$ZIG_GLOBAL_CACHE_DIR"

cd tools/raw-stack
exec zig build test --summary all
