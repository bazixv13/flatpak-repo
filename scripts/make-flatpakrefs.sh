#!/usr/bin/env bash
# Write a .flatpakref for every published app ref into a directory.
#
#   ./scripts/make-flatpakrefs.sh <outdir>
#
# A .flatpakref is what makes "Install" in GNOME Software or Bazaar work with
# one click: it carries the remote URL and the key, so nothing has to be typed
# on a terminal. RuntimeRepo points at Flathub so the runtime an app needs is
# resolved even for a user who never added Flathub themselves.
#
# The file is named after the ref, <app-id>.<branch>.flatpakref, so a beta
# branch never overwrites the stable link.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

OUT_DIR="${1:-}"
[[ -n "$OUT_DIR" ]] || {
  echo "usage: $0 <outdir>" >&2
  exit 1
}
[[ -d "$REPO_DIR/refs/heads/app" ]] || {
  echo "No app refs in $REPO_DIR" >&2
  exit 1
}

SITE_URL="${SITE_URL:-https://bazixv13.github.io/flatpak-repo/}"
RUNTIME_REPO="${RUNTIME_REPO:-https://flathub.org/repo/flathub.flatpakrepo}"
REMOTE_NAME="${REMOTE_NAME:-bazixv13-apps}"

# One source of truth for the key: the descriptor publish.sh just regenerated.
KEY_B64="$(sed -n 's/^GPGKey=//p' "$ROOT/flatpakrepo")"
[[ -n "$KEY_B64" ]] || {
  echo "No GPGKey in $ROOT/flatpakrepo; run make-flatpakrepo.sh first." >&2
  exit 1
}

mkdir -p "$OUT_DIR"
# Refuse to leave a link from a previous branch layout behind.
rm -f "$OUT_DIR"/*.flatpakref

count=0
while IFS=/ read -r _ app_id _arch branch; do
  [[ -n "${branch:-}" ]] || continue
  file="$app_id.$branch.flatpakref"
  cat > "$OUT_DIR/$file" <<EOF
[Flatpak Ref]
Title=${app_id##*.}
Name=$app_id
Branch=$branch
Url=$SITE_URL
RuntimeRepo=$RUNTIME_REPO
IsRuntime=false
SuggestRemoteName=$REMOTE_NAME
GPGKey=$KEY_B64
EOF
  echo ">> Wrote $file"
  count=$((count + 1))
done < <(find "$REPO_DIR/refs/heads/app" -type f | sort |
  sed "s|^$REPO_DIR/refs/heads/||")

[[ $count -gt 0 ]] || {
  echo "No app refs found under $REPO_DIR/refs/heads/app" >&2
  exit 1
}
