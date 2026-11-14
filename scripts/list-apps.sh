#!/usr/bin/env bash
# List the apps currently present in the local repository.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [[ ! -d "$REPO_DIR/refs/heads/app" ]]; then
  echo "No apps found. Run ./scripts/sync-repo.sh first." >&2
  exit 0
fi

cd "$REPO_DIR/refs/heads/app"
find . -type f | sed 's#^\./##' | sort
