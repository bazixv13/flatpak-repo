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
    || echo "https://github.com/bazixv13/hideaway-flatpak.git"
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
