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
# Wrap in command substitution + printf so the trailing newline that git
# always appends is dropped — readme2modulestrings.py does a strict
# 4-tuple unpack on split('\n'), so an extra trailing empty string would
# raise ValueError.
out=$(git log -1 --format='%ct 0%n%h%n%an%n%s' . 2>/dev/null) || true
if [ -n "$out" ]; then
    printf '%s' "$out"
else
    # Fallback when git history is unavailable (e.g. tarball checkout).
    printf '0 0\n0000000\nunknown\nno git history available'
fi
