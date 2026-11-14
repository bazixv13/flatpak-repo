#!/usr/bin/env bash
# Create the GPG key used to sign this Flatpak repository, then regenerate
# flatpakrepo so it carries the matching public key.
#
#   ./scripts/init-signing-key.sh
#
# Run this once. The key lives in $GPG_HOMEDIR (default ~/.config/flatpak-repo-gpg)
# and is NOT committed: only the public key (repo-key.asc) and the base64 form
# inside flatpakrepo are published.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd gpg

NAME="${GPG_NAME:-bazixv13 Apps Flatpak Repository}"
EMAIL="${GPG_EMAIL:-bazixv13@users.noreply.github.com}"

mkdir -p "$GPG_HOMEDIR"
chmod 700 "$GPG_HOMEDIR"

if gpg --homedir "$GPG_HOMEDIR" --list-secret-keys --with-colons 2>/dev/null | grep -q '^sec:'; then
  echo ">> A signing key already exists in $GPG_HOMEDIR"
else
  echo ">> Generating signing key in $GPG_HOMEDIR ..."
  gpg --homedir "$GPG_HOMEDIR" --batch --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Name-Real: $NAME
Name-Email: $EMAIL
Expire-Date: 0
%commit
EOF
fi

require_gpg_key
echo ">> Signing key: $GPG_KEY_ID"

echo ">> Exporting public key ..."
gpg --homedir "$GPG_HOMEDIR" --armor --export "$GPG_KEY_ID" > "$ROOT/repo-key.asc"

echo ">> Regenerating flatpakrepo with embedded GPGKey ..."
"$(dirname "${BASH_SOURCE[0]}")/make-flatpakrepo.sh"

echo
echo "Done. Next:"
echo "  ./scripts/sync-repo.sh   # or add-app.sh"
echo "  ./scripts/publish.sh"
