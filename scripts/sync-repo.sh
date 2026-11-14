#!/usr/bin/env bash
# Download the currently published OSTree repo (gh-pages branch) into ./repo
# so new apps are added on top of what is already published.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd git
require_cmd rsync

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo ">> Fetching published repo from gh-pages ..."
git clone --quiet --branch gh-pages --depth 1 "$(origin_url)" "$TMP/pages"

mkdir -p "$REPO_DIR"
rsync -a --delete \
  --exclude '.git' \
  --exclude 'flatpakrepo' \
  --exclude '.nojekyll' \
  "$TMP/pages/" "$REPO_DIR/"

echo ">> Local repo is up to date: $REPO_DIR"
