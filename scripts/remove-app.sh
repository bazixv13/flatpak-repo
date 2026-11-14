#!/usr/bin/env bash
# Remove an app from the local repository.
#
#   ./scripts/remove-app.sh io.github.bazixv13.Hideaway
#
# Then run ./scripts/publish.sh to push the change to GitHub Pages.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

APP_ID="${1:?Usage: $0 <app-id>}"
[[ -d "$REPO_DIR" ]] || {
  echo "No local repo at $REPO_DIR. Run ./scripts/sync-repo.sh first." >&2
  exit 1
}

APP_REF_DIR="$REPO_DIR/refs/heads/app/$APP_ID"
if [[ ! -d "$APP_REF_DIR" ]]; then
  echo "App '$APP_ID' not found in $REPO_DIR/refs/heads/app/" >&2
  echo "Available apps:" >&2
  "$(dirname "${BASH_SOURCE[0]}")/list-apps.sh" >&2 || true
  exit 1
fi

echo ">> Removing refs for $APP_ID ..."
find "$APP_REF_DIR" -type f -delete
find "$REPO_DIR/refs/heads/app" -mindepth 1 -type d -empty -delete 2>/dev/null || true

echo ">> Signing and refreshing repository metadata ..."
sign_repo "$REPO_DIR"

echo
echo "Removed $APP_ID from the local repo."
echo "Objects are still on disk; reclaim space with:"
echo "  ostree --repo=\"$REPO_DIR\" prune --refs-only"
echo "Publish the change with:  ./scripts/publish.sh"
