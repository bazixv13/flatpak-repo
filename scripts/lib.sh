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
# branch whenever the appstream data changes. An unsigned appstream commit
# makes `flatpak update --appstream` fail, so app stores such as Bazaar cannot
# list the apps.
#
# The binding has to be an array of refs, not a string: flatpak reads
# `ostree.ref-binding` as a string array, and its privileged appstream path
# rejects a commit whose binding is a plain string with "Commit for
# 'appstream2/x86_64' has no ref binding". That only shows up for system
# installations, where the update is deployed by the system helper; pulling as
# root directly never looks at the binding, so the bug stays invisible there.
# `ostree commit --branch` writes the array for us.
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
    # `--branch` records the ref binding, as the array flatpak expects.
    if ! new="$(ostree --repo="$repo" commit --branch="$name/$ARCH" \
        --tree=ref="$old" --parent=none \
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

# Rewrite the summary from the refs that exist now, and sign it.
#
# `flatpak build-update-repo --no-update-appstream` is what this wants to be,
# but flatpak older than about 1.16 still writes the appstream commit it would
# have created into the summary while not writing the commit itself, so the
# summary advertises a commit that is not in the repository. Clients then fail
# with "No such metadata object ...commit", and Bazaar or GNOME Software cannot
# refresh their app list. ostree rebuilds the summary from the real refs,
# phantom entries and all.
#
# The summary index describes the previous summary, so it is removed rather
# than left to disagree with the new one; clients fall back to the full summary
# when it is missing.
resign_summary() {
  local repo="${1:-$REPO_DIR}"
  require_gpg_key
  # ostree fails to rebuild the summary when this directory is absent.
  mkdir -p "$repo/refs/remotes"
  ostree --repo="$repo" summary -u \
    --gpg-sign="$GPG_KEY_ID" --gpg-homedir="$GPG_HOMEDIR" \
    --add-metadata="xa.title='bazixv13 Apps'" \
    --add-metadata="xa.comment='Flatpak repository for bazixv13 apps'"
  rm -f "$repo/summary.idx" "$repo/summary.idx.sig"
}

# Print the commit the summary advertises for a ref, if it advertises one.
summary_commit_for() {
  local repo="$1" ref="$2"
  ostree --repo="$repo" summary -v 2>/dev/null \
    | awk -v want="$ref" '
        /^\* / { current = substr($0, 3); next }
        current == want && /^[[:space:]]+[0-9a-f]+$/ {
          gsub(/[[:space:]]/, ""); print; exit
        }
      '
}

# Refuse to publish a repository whose summary and refs disagree.
#
# That mismatch is invisible locally: the refs are fine, so installs from a
# file: URL work, while every HTTP client (and the app stores) fail on the
# summary. Check it here so a broken publish fails the run instead of the
# users' updates.
verify_repo() {
  local repo="${1:-$REPO_DIR}" ref rel tip advertised failed=0
  while IFS= read -r ref; do
    rel="${ref#"$repo"/refs/heads/}"
    tip="$(cat "$ref")"
    advertised="$(summary_commit_for "$repo" "$rel")"
    if [[ "$advertised" != "$tip" ]]; then
      echo "Summary advertises '${advertised:-nothing}' for $rel, ref is $tip" >&2
      failed=1
    fi
    if [[ ! -f "$repo/objects/${tip:0:2}/${tip:2}.commit" ]]; then
      echo "Commit $tip for $rel is missing from the repository" >&2
      failed=1
    fi
    # The binding must be an array containing the ref. A string binding (what
    # `ostree commit --add-metadata-string=ostree.ref-binding=...` writes) is
    # accepted by root but rejected by flatpak's privileged appstream deploy.
    binding="$(ostree --repo="$repo" show "$tip" --print-metadata-key=ostree.ref-binding 2>/dev/null || true)"
    if [[ "$binding" != \[* || "$binding" != *"'$rel'"* ]]; then
      echo "Commit $tip for $rel has ref binding '${binding:-none}', expected an array containing '$rel'" >&2
      failed=1
    fi
    # An unsigned commit is accepted by the server and then rejected by every
    # client that verifies signatures, which is all of them. Signatures are
    # detached metadata, so they show up as a "Found N signatures" header
    # rather than as a metadata key.
    if ! LC_ALL=C ostree --repo="$repo" show "$tip" 2>/dev/null |
      grep -q '^Found [1-9][0-9]* signature'; then
      echo "Commit $tip for $rel is not signed" >&2
      failed=1
    fi
  done < <(find "$repo/refs/heads" -type f)
  # The other direction: a summary that advertises a ref which does not exist
  # makes clients fail to update appstream.
  while IFS= read -r rel; do
    [[ -f "$repo/refs/heads/$rel" ]] && continue
    case "$rel" in
      app/*|runtime/*|appstream/*|appstream2/*)
        echo "Summary advertises $rel, but no such ref exists" >&2
        failed=1
        ;;
    esac
  done < <(ostree --repo="$repo" summary -v 2>/dev/null | awk '/^\* /{print substr($0,3)}')
  if [[ $failed -ne 0 ]]; then
    echo "The repository is inconsistent and was not published." >&2
    return 1
  fi
  echo ">> Summary and refs agree."
}

# Sign every app commit in $REPO_DIR, the appstream branches, and the summary.
#
# Order matters: build-update-repo regenerates the appstream branch, so the
# appstream commits are signed afterwards and the summary is refreshed last so
# it advertises the signed commits.
sign_repo() {
  local repo="${1:-$REPO_DIR}"
  require_gpg_key
  # Both signing and delta generation list every ref including refs/remotes,
  # and the published repository has no such directory, so they would abort
  # with "opendir(refs/remotes): No such file or directory" on a valid repo.
  mkdir -p "$repo/refs/remotes"
  # No ID: sign every ref in the repository. Signing one app at a time left
  # the Debug runtime refs unsigned, and a user pulling one of those gets a
  # verification failure.
  flatpak build-sign --gpg-sign="$GPG_KEY_ID" --gpg-homedir="$GPG_HOMEDIR" "$repo"
  # --generate-static-deltas makes an update download only the objects that
  # changed; without it every update re-downloads the whole app commit.
  # --prune drops objects nothing refers to any more, mostly the appstream
  # commits replaced on each publish, which otherwise grow the tree forever.
  flatpak build-update-repo --gpg-sign="$GPG_KEY_ID" --gpg-homedir="$GPG_HOMEDIR" \
    --generate-static-deltas --prune \
    --title="bazixv13 Apps" --comment="Flatpak repository for bazixv13's apps" "$repo"
  sign_appstream "$repo"
  # Refresh the summary so it advertises the signed appstream commits. This
  # must NOT regenerate the appstream branch, or it would discard the
  # signatures applied above.
  resign_summary "$repo"
}
