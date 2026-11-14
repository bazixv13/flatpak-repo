#!/usr/bin/env bash
# Push the local repository (./repo) to the gh-pages branch, which GitHub Pages serves.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd git
require_cmd rsync

[[ -f "$REPO_DIR/summary" ]] || {
  echo "No repo to publish at $REPO_DIR. Run add-app.sh first." >&2
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo ">> Cloning gh-pages ..."
git clone --quiet --branch gh-pages --depth 1 "$(origin_url)" "$TMP/pages"

echo ">> Syncing OSTree objects ..."
rsync -a --delete \
  --exclude '.git' \
  --exclude 'flatpakrepo' \
  --exclude '.nojekyll' \
  "$REPO_DIR/" "$TMP/pages/"

# Keep the repo-level helper files at the site root.
cp "$ROOT/flatpakrepo" "$TMP/pages/flatpakrepo"
cp "$ROOT/.nojekyll" "$TMP/pages/.nojekyll"

cd "$TMP/pages"
git add -A
if git diff --cached --quiet; then
  echo ">> No changes to publish."
  exit 0
fi

git commit --quiet -m "Update Flatpak repo ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
git push --quiet origin gh-pages

echo ">> Published: https://bazixv13.github.io/hideaway-flatpak/"
