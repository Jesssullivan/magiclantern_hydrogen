#!/usr/bin/env bash
# Bazel sh_test entry — chdir into the workspace and invoke zig build test.
set -euo pipefail

# Bazel sets BUILD_WORKSPACE_DIRECTORY when running under `bazel run` /
# `bazel test`; fall back to PWD if unset (allows manual invocation).
cd "${BUILD_WORKSPACE_DIRECTORY:-$PWD}"
cd tools/raw-stack
exec zig build test --summary all
