#!/usr/bin/env bash
# Bring the published remote up to date with every app's newest upstream release.
#
# This is the whole loop in one command:
#
#   1. ask each manifest's upstream for its newest tag
#   2. rewrite the URL and checksum when it moved
#   3. rebuild only the apps that changed
#   4. sign, refresh the summary, publish to gh-pages
#   5. commit the manifest changes back to main
#
# Safe to run on a timer: with nothing new it exits without touching the
# published repo.
#
#   ./scripts/update-all.sh              # update, build, publish
#   ./scripts/update-all.sh --check      # report only
#   ./scripts/update-all.sh --no-build   # refresh manifests, skip the build
#
# Exit codes: 0 = fine (changed or not), 1 = something failed.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CHECK_ONLY=0
DO_BUILD=1
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --no-build) DO_BUILD=0 ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

require_cmd python3
require_cmd git

cd "$ROOT"

echo ">> Checking upstream releases ..."
UPDATE_LOG="$(mktemp)"
trap 'rm -f "$UPDATE_LOG"' EXIT

if ! ./scripts/update_manifests.py $([[ $CHECK_ONLY -eq 1 ]] && echo --check) | tee "$UPDATE_LOG"; then
  echo "Manifest update failed." >&2
  exit 1
fi

# Which apps actually moved, one app id per line.
CHANGED="$(sed -n '/^---RESULT---$/,$p' "$UPDATE_LOG" | tail -n +2 \
  | python3 -c 'import json,sys; print("\n".join(r["app"] for r in json.load(sys.stdin) if r["status"]=="updated"))')"

if [[ -z "$CHANGED" ]]; then
  if [[ $FORCE -eq 0 ]]; then
    echo ">> Everything is already at its newest upstream release."
    exit 0
  fi
  # --force rebuilds every app even with no upstream change, which is how a
  # broken publish gets repaired without waiting for a new release.
  echo ">> Forcing a rebuild of every app."
  CHANGED="$(python3 -c '
import json, pathlib
for path in sorted(pathlib.Path("apps").glob("*.json")):
    if path.name == "cargo-sources.json":
        continue
    print(json.loads(path.read_text())["app-id"])
')"
fi

echo ">> Updated: $(echo "$CHANGED" | tr '\n' ' ')"

if [[ $CHECK_ONLY -eq 1 ]]; then
  exit 0
fi

if [[ $DO_BUILD -eq 1 ]]; then
  # Rebuild from the published repo so new apps are added on top of what is
  # already live, and existing ones keep their history.
  ./scripts/sync-repo.sh

  while IFS= read -r app_id; do
    [[ -n "$app_id" ]] || continue
    manifest="$(grep -l "\"$app_id\"" apps/*.json | head -n1)"
    [[ -n "$manifest" ]] || { echo "No manifest for $app_id" >&2; exit 1; }
    echo ">> Rebuilding $app_id ..."
    ./scripts/add-app.sh "$manifest"
  done <<< "$CHANGED"

  echo ">> Publishing ..."
  ./scripts/publish.sh
fi

# Record the new pins on main so the next run starts from them.
if ! git diff --quiet -- apps/; then
  git add apps/
  git commit --quiet -m "Update app sources ($(date -u +%Y-%m-%d))"
  git push --quiet origin "$(git branch --show-current)"
  echo ">> Committed manifest updates."
fi

echo ">> Done."
