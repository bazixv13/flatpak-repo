#!/usr/bin/env bash
# Build a Flatpak manifest and export it into the local repository.
#
#   ./scripts/add-app.sh apps/io.github.bazixv13.Hideaway.json
#
# After it succeeds, run ./scripts/publish.sh to push the result to GitHub Pages.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MANIFEST="${1:?Usage: $0 <path-to-manifest.json>}"
[[ -f "$MANIFEST" ]] || { echo "Manifest not found: $MANIFEST" >&2; exit 1; }

require_cmd flatpak-builder
require_cmd python3

APP_ID="$(manifest_field "$MANIFEST" app-id)"
BRANCH="$(manifest_field "$MANIFEST" branch master)"
[[ -n "$APP_ID" ]] || { echo "Manifest is missing 'app-id'" >&2; exit 1; }

mkdir -p "$REPO_DIR"
if [[ ! -f "$REPO_DIR/config" ]]; then
  echo ">> Initializing local OSTree repo at $REPO_DIR"
  ostree init --repo="$REPO_DIR" --mode=archive
fi

echo ">> Building $APP_ID (branch: $BRANCH, arch: $ARCH) ..."
# --install-deps-from lets flatpak-builder fetch the runtime, SDK and SDK
# extensions a manifest names. Without it a fresh machine (or a CI runner)
# fails with "org.gnome.Sdk/x86_64/50 not installed".
flatpak-builder --user --force-clean --disable-rofiles-fuse \
  --install-deps-from=flathub \
  --state-dir="$STATE_DIR" \
  --repo="$REPO_DIR" \
  --default-branch="$BRANCH" \
  --arch="$ARCH" \
  "$BUILD_DIR/$APP_ID" "$MANIFEST"

echo ">> Signing and refreshing repository metadata ..."
sign_repo "$REPO_DIR"

echo
echo "Added $APP_ID to the local repo."
echo "Publish it with:  ./scripts/publish.sh"
