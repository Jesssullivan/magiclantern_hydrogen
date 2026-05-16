#!/bin/sh

# Called from readme2modulestrings.py.
# Emits four newline-separated values describing the last change that
# touched the current directory:
#
#   <unix_seconds> <tz_offset_seconds>
#   <short_hash>
#   <author>
#   <commit message, first line>
#
# The format matches what the legacy Mercurial template produced so the
# downstream Python parser does not need adjustment.

set -e

# Use git log limited to the current working directory. -1 = most recent.
git log -1 --format='%ct 0%n%h%n%an%n%s' . 2>/dev/null || {
    # Fallback when git history is unavailable (e.g. tarball checkout).
    printf '0 0\n0000000\nunknown\nno git history available\n'
}
