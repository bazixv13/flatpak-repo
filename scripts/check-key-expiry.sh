#!/usr/bin/env bash
# Fail when the repository signing key has expired or is about to.
#
#   ./scripts/check-key-expiry.sh [KEY_FILE] [DAYS]
#
# KEY_FILE defaults to repo-key.asc, DAYS to 30. An expired key is not a
# broken repository — it is every client refusing to verify anything, with an
# error that says nothing about expiry, so check before it happens.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd gpg

KEY_FILE="${1:-$ROOT/repo-key.asc}"
DAYS="${2:-30}"

[[ -f "$KEY_FILE" ]] || {
  echo "No key file at $KEY_FILE" >&2
  exit 1
}

HOMEDIR="$(mktemp -d)"
trap 'rm -rf "$HOMEDIR"' EXIT

export GNUPGHOME="$HOMEDIR"
chmod 700 "$HOMEDIR"
gpg --quiet --import "$KEY_FILE" 2>/dev/null || {
  echo "Could not import $KEY_FILE" >&2
  exit 1
}

# The pub record carries the expiry as a Unix timestamp in field 7, empty when
# the key never expires.
expires="$(gpg --with-colons --list-keys | awk -F: '/^pub:/{print $7; exit}')"
fingerprint="$(gpg --with-colons --list-keys | awk -F: '/^fpr:/{print $10; exit}')"

if [[ -z "$expires" ]]; then
  echo ">> Signing key $fingerprint does not expire."
  exit 0
fi

pretty="$(date -u -d "@$expires" +%Y-%m-%d)"
now="$(date +%s)"
horizon=$((now + DAYS * 86400))

if ((expires <= now)); then
  echo "Signing key $fingerprint expired on $pretty; clients cannot verify the repository." >&2
  exit 1
fi
if ((expires <= horizon)); then
  echo "Signing key $fingerprint expires on $pretty, less than $DAYS days away." >&2
  exit 1
fi

echo ">> Signing key $fingerprint valid until $pretty."
