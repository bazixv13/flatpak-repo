#!/usr/bin/env bash
# Shared helpers for the Hideaway Flatpak repository tooling.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="${REPO_DIR:-$ROOT/repo}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
STATE_DIR="${STATE_DIR:-$ROOT/.flatpak-builder}"
ARCH="${ARCH:-$(flatpak --default-arch)}"

# Print the git remote URL of this repository (falls back to the canonical URL).
origin_url() {
  git -C "$ROOT" remote get-url origin 2>/dev/null \
    || echo "https://github.com/bazixv13/flatpak-repo.git"
}

# Fail early when a required executable is missing.
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

# Read a top-level field from a Flatpak manifest.
# usage: manifest_field <manifest.json> <field> [default]
manifest_field() {
  python3 - "$@" <<'PY'
import json, sys
path, field = sys.argv[1], sys.argv[2]
default = sys.argv[3] if len(sys.argv) > 3 else ""
with open(path) as handle:
    data = json.load(handle)
value = data.get(field, default)
print(value if value is not None else default)
PY
}

# --- GPG signing ---------------------------------------------------------
# The repository is GPG-signed so `flatpak install` works at system scope.
# An unsigned remote is added with no-gpg-verify, and Flatpak then refuses to
# pull it as root ("Can't pull from untrusted non-gpg verified remote").
GPG_KEY_ID="${GPG_KEY_ID:-}"
GPG_HOMEDIR="${GPG_HOMEDIR:-$HOME/.config/flatpak-repo-gpg}"

# Print the signing key id, or fail with a useful message.
require_gpg_key() {
  if [[ -z "$GPG_KEY_ID" ]]; then
    GPG_KEY_ID="$(gpg --homedir "$GPG_HOMEDIR" --list-secret-keys --with-colons 2>/dev/null \
      | awk -F: '/^fpr:/ {print $10; exit}')"
  fi
  [[ -n "$GPG_KEY_ID" ]] || {
    echo "No GPG signing key found in $GPG_HOMEDIR." >&2
    echo "Create one with: ./scripts/init-signing-key.sh" >&2
    exit 1
  }
  export GPG_HOMEDIR GPG_KEY_ID
}

# Sign the appstream refs in $REPO_DIR.
#
# `flatpak build-sign` refuses these names ("Names must contain at least 2
# periods"), so re-commit each appstream branch with ostree and a signature.
# This has to happen after build-update-repo, which regenerates the appstream
# branch unsigned whenever the appstream data changes. An unsigned appstream
# commit makes `flatpak update --appstream` fail, so app stores such as Bazaar
# cannot list the apps.
sign_appstream() {
  local repo="${1:-$REPO_DIR}"
  require_gpg_key
  local name ref old ts new
  for name in appstream appstream2; do
    ref="$repo/refs/heads/$name/$ARCH"
    [[ -f "$ref" ]] || continue
    old="$(cat "$ref")"
    ts="$(ostree --repo="$repo" show "$old" 2>/dev/null \
      | awk '/^Date:/{print $2" "$3" "$4}')"
    [[ -n "$ts" ]] || { echo "Could not read date of $name/$ARCH" >&2; exit 1; }
    if ! new="$(ostree --repo="$repo" commit --branch="$name/$ARCH" \
        --tree=ref="$old" --parent=none \
        --add-metadata-string="ostree.ref-binding=$name/$ARCH" \
        --subject="Update" \
        --gpg-sign="$GPG_KEY_ID" --gpg-homedir="$GPG_HOMEDIR" \
        --timestamp="$ts")"; then
      echo "Failed to sign $name/$ARCH" >&2
      exit 1
    fi
    # only write the ref once the commit actually succeeded
    printf '%s\n' "$new" > "$ref"
    echo ">> Signed $name/$ARCH ($new)"
  done
}

# Sign every app commit in $REPO_DIR, the appstream branches, and the summary.
#
# Order matters: build-update-repo regenerates the appstream branch, so the
# appstream commits are signed afterwards and the summary is refreshed last so
# it advertises the signed commits.
sign_repo() {
  local repo="${1:-$REPO_DIR}"
  require_gpg_key
  if [[ -d "$repo/refs/heads/app" ]]; then
    while IFS= read -r ref; do
      local rel="${ref#"$repo"/refs/heads/}"
      local id="${rel#app/}"; id="${id%%/*}"
      local branch="${rel##*/}"
      flatpak build-sign --gpg-sign="$GPG_KEY_ID" --gpg-homedir="$GPG_HOMEDIR" \
        "$repo" "$id" "$branch"
    done < <(find "$repo/refs/heads/app" -type f)
  fi
  flatpak build-update-repo --gpg-sign="$GPG_KEY_ID" --gpg-homedir="$GPG_HOMEDIR" \
    --title="bazixv13 Apps" --comment="Flatpak repository for bazixv13's apps" "$repo"
  sign_appstream "$repo"
  # Refresh the summary so it advertises the signed appstream commits. This
  # second call must NOT regenerate the appstream branch, or it would discard
  # the signatures applied above. --no-update-appstream keeps the branches as
  # they are and only rewrites summary/summary.sig.
  flatpak build-update-repo --no-update-appstream \
    --gpg-sign="$GPG_KEY_ID" --gpg-homedir="$GPG_HOMEDIR" \
    --title="bazixv13 Apps" --comment="Flatpak repository for bazixv13's apps" "$repo"
}
