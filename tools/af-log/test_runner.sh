#!/usr/bin/env bash
# Bazel sh_test entry. See tools/raw-stack/test_runner.sh for env rationale.

set -euo pipefail
cd "${BUILD_WORKSPACE_DIRECTORY:-$PWD}"
export ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-cache-global"
mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
cd tools/af-log
exec zig build test --summary all
