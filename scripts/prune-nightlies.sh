#!/usr/bin/env bash
# Prune old nightly releases for magiclantern_hydrogen.
#
# Keeps the N newest 'nightly-*' GitHub releases; deletes the rest including
# their git tags. Idempotent. Safe to run repeatedly.
#
# Env:
#   KEEP            Number of nightlies to retain (default 7).
#   REPO            owner/repo (default: Jesssullivan/magiclantern_hydrogen).
#   DRY_RUN         if set, prints what would be deleted but does not delete.

set -euo pipefail

KEEP="${KEEP:-7}"
REPO="${REPO:-Jesssullivan/magiclantern_hydrogen}"

echo "prune-nightlies.sh: repo=${REPO} keep=${KEEP}${DRY_RUN:+ (DRY_RUN)}"

# Pull every release, filter to nightly-*, sort by createdAt descending.
# jq's `sort_by` is ascending; reverse to get newest-first.
to_delete=$(
  gh release list --repo "$REPO" --limit 200 --json tagName,createdAt \
    --jq '[.[] | select(.tagName | startswith("nightly-"))] | sort_by(.createdAt) | reverse | .['"$KEEP"':][] | .tagName'
)

if [ -z "$to_delete" ]; then
  echo "Nothing to prune."
  exit 0
fi

while IFS= read -r tag; do
  [ -z "$tag" ] && continue
  if [ -n "${DRY_RUN:-}" ]; then
    echo "[DRY_RUN] would delete: $tag"
    continue
  fi
  echo "Deleting release + tag: $tag"
  gh release delete "$tag" --repo "$REPO" --cleanup-tag --yes || true
done <<< "$to_delete"

echo "prune-nightlies.sh done."
