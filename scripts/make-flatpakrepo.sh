#!/usr/bin/env bash
# Regenerate ./flatpakrepo with the current signing key embedded as GPGKey=.
#
#   ./scripts/make-flatpakrepo.sh
#
# The GPGKey field is what makes Flatpak add the remote WITH verification.
# Without it the remote is registered no-gpg-verify, and system-scope installs
# then fail with "Can't pull from untrusted non-gpg verified remote".
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd gpg
require_cmd python3
require_gpg_key

SITE_URL="${SITE_URL:-https://bazixv13.github.io/flatpak-repo/}"
HOMEPAGE="${HOMEPAGE:-https://github.com/bazixv13/flatpak-repo}"
# The runtime an app needs (org.gnome.Platform) lives on Flathub. Naming it
# here means a user who never added Flathub is prompted for it instead of
# getting "runtime not found".
RUNTIME_REPO="${RUNTIME_REPO:-https://flathub.org/repo/flathub.flatpakrepo}"

# Base64 of the binary public key, on one line, as Flatpak expects.
KEY_B64="$(gpg --homedir "$GPG_HOMEDIR" --export "$GPG_KEY_ID" | base64 -w0)"

python3 - "$ROOT/flatpakrepo" "$SITE_URL" "$HOMEPAGE" "$KEY_B64" "$RUNTIME_REPO" <<'PY'
import sys
path, url, homepage, key, runtime_repo = sys.argv[1:6]
body = f"""[Flatpak Repo]
Title=bazixv13 Apps
Url={url}
Homepage={homepage}
Comment=Flatpak repository for bazixv13's apps
Description=Flatpak repository for bazixv13's apps (Hideaway and more)
Icon={url}logo.svg
RuntimeRepo={runtime_repo}
GPGKey={key}
"""
open(path, "w").write(body)
print(f">> Wrote {path} ({len(body)} bytes, GPGKey embedded)")
PY
