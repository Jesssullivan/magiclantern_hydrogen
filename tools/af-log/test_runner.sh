#!/usr/bin/env bash
set -euo pipefail
cd "${BUILD_WORKSPACE_DIRECTORY:-$PWD}"
cd tools/af-log
exec zig build test --summary all
