#!/usr/bin/env python3
"""Point every app manifest at its upstream's newest release tag.

Each manifest in apps/ carries the app's source as a GitHub tag archive:

    "url": "https://github.com/<owner>/<repo>/archive/refs/tags/<tag>.tar.gz",
    "sha256": "..."

This script finds that source, asks GitHub for the newest tag, and rewrites
both the URL and the checksum when it has moved. It never guesses: the
checksum is computed from the archive it just downloaded, so a manifest can
only ever point at bytes that were really fetched and hashed.

Exit status is 0 whether or not anything changed; the machine-readable
summary on stdout says what happened, so the caller can decide to rebuild.

    ./scripts/update_manifests.py [--check] [--only APP_ID]

--check reports what would change without writing anything.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPS_DIR = ROOT / "apps"

# github.com/<owner>/<repo>/archive/refs/tags/<tag>.tar.gz
ARCHIVE_RE = re.compile(
    r"^https://github\.com/(?P<repo>[^/]+/[^/]+)/archive/refs/tags/(?P<tag>[^/]+)\.tar\.gz$"
)

# Tags we are willing to treat as releases: v1.2.3, 1.2.3, v1.2, v1
TAG_RE = re.compile(r"^v?\d+(?:\.\d+)*$")


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def version_key(tag: str) -> tuple[int, ...]:
    """Sort key that orders 0.3.9 before 0.3.10 and 1.4 before 1.4.1."""
    parts = tag.lstrip("v").split(".")
    return tuple(int(part) for part in parts)


def latest_tag(repo: str) -> str | None:
    """Newest release-like tag in a GitHub repository.

    Uses `git ls-remote` rather than the REST API: it needs no token, has no
    rate limit, and sees tags that never got a GitHub release attached (the
    Hideaway repo tags ahead of its releases).
    """
    result = run(["git", "ls-remote", "--tags", f"https://github.com/{repo}.git"])
    if result.returncode != 0:
        print(f"  ! could not list tags for {repo}: {result.stderr.strip()}", file=sys.stderr)
        return None

    tags: list[str] = []
    for line in result.stdout.splitlines():
        ref = line.split("\t")[-1]
        if not ref.startswith("refs/tags/"):
            continue
        tag = ref[len("refs/tags/"):]
        if tag.endswith("^{}"):  # peeled annotated tag, same tag
            tag = tag[:-3]
        if TAG_RE.match(tag):
            tags.append(tag)

    if not tags:
        return None
    return max(set(tags), key=version_key)


def sha256_of(url: str) -> str | None:
    """Download an archive and hash it. Returns None on any failure."""
    try:
        with urllib.request.urlopen(url, timeout=180) as response:
            digest = hashlib.sha256()
            while True:
                chunk = response.read(1 << 20)
                if not chunk:
                    break
                digest.update(chunk)
            return digest.hexdigest()
    except Exception as error:  # noqa: BLE001 - any failure means "do not use this"
        print(f"  ! could not fetch {url}: {error}", file=sys.stderr)
        return None


GIT_SOURCE_RE = re.compile(r"^https://github\.com/(?P<repo>[^/]+/[^/]+?)(?:\.git)?$")


def find_git_source(manifest: dict) -> dict | None:
    """A source that pins a GitHub tag on a git source instead of an archive."""
    app_id = manifest.get("app-id", "")
    modules = manifest.get("modules", [])
    wanted = {
        app_id,
        app_id.lower(),
        app_id.split(".")[-1],
        app_id.split(".")[-1].lower(),
    }

    def candidates(module: dict):
        for source in module.get("sources", []):
            if not isinstance(source, dict) or source.get("type") != "git":
                continue
            if GIT_SOURCE_RE.match(source.get("url", "")) and source.get("tag"):
                yield source

    for module in modules:
        if module.get("name") in wanted:
            for source in candidates(module):
                return source
    found = [source for module in modules for source in candidates(module)]
    return found[-1] if found else None


def find_archive_source(manifest: dict) -> dict | None:
    """The source entry that points at the app's own upstream tag archive.

    A manifest can carry several GitHub tag archives: localsend-adwaita also
    builds wl-clipboard from one. Only the archive belonging to the module
    named after the app id is the app's own source, so match on that rather
    than taking the first archive found.
    """
    app_id = manifest.get("app-id", "")
    modules = manifest.get("modules", [])

    def archives(module: dict):
        for source in module.get("sources", []):
            if isinstance(source, dict) and source.get("type") == "archive":
                if ARCHIVE_RE.match(source.get("url", "")):
                    yield source

    # The app's module is conventionally named after the app id, sometimes
    # with the id lowercased or the final segment only.
    wanted = {
        app_id,
        app_id.lower(),
        app_id.split(".")[-1],
        app_id.split(".")[-1].lower(),
    }
    for module in modules:
        if module.get("name") in wanted:
            for source in archives(module):
                return source

    # Fall back to the last archive in the manifest: dependencies are listed
    # before the app itself.
    found = [source for module in modules for source in archives(module)]
    return found[-1] if found else None


def process(path: Path, check_only: bool) -> dict:
    manifest = json.loads(path.read_text())
    app_id = manifest.get("app-id", path.stem)

    source = find_archive_source(manifest)
    is_git = False
    if source is None:
        source = find_git_source(manifest)
        is_git = source is not None
    if source is None:
        return {"app": app_id, "status": "skipped", "reason": "no GitHub tag source"}

    if is_git:
        match = GIT_SOURCE_RE.match(source["url"])
        repo = match.group("repo")
        current_tag = source["tag"]
    else:
        match = ARCHIVE_RE.match(source["url"])
        repo = match.group("repo")
        current_tag = match.group("tag")

    newest = latest_tag(repo)
    if newest is None:
        return {"app": app_id, "status": "skipped", "reason": f"no release tags in {repo}"}

    if version_key(newest) <= version_key(current_tag):
        return {
            "app": app_id,
            "status": "current",
            "tag": current_tag,
            "repo": repo,
        }

    new_url = f"https://github.com/{repo}/archive/refs/tags/{newest}.tar.gz"
    if check_only:
        return {
            "app": app_id,
            "status": "outdated",
            "from": current_tag,
            "to": newest,
            "repo": repo,
        }

    if is_git:
        # A git source is pinned by tag only; flatpak resolves the commit.
        source["tag"] = newest
        path.write_text(json.dumps(manifest, indent=4) + "\n")
        return {
            "app": app_id,
            "status": "updated",
            "from": current_tag,
            "to": newest,
            "repo": repo,
        }

    digest = sha256_of(new_url)
    if digest is None:
        return {
            "app": app_id,
            "status": "skipped",
            "reason": f"could not hash {newest}",
            "repo": repo,
        }

    source["url"] = new_url
    source["sha256"] = digest
    path.write_text(json.dumps(manifest, indent=4) + "\n")

    return {
        "app": app_id,
        "status": "updated",
        "from": current_tag,
        "to": newest,
        "repo": repo,
        "sha256": digest,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="report only, write nothing")
    parser.add_argument("--only", help="limit to one app id")
    args = parser.parse_args()

    manifests = sorted(
        path
        for path in APPS_DIR.glob("*.json")
        if path.name != "cargo-sources.json"
    )
    if args.only:
        manifests = [
            path
            for path in manifests
            if json.loads(path.read_text()).get("app-id") == args.only
        ]
        if not manifests:
            print(f"No manifest for app id {args.only}", file=sys.stderr)
            return 1

    results = []
    for path in manifests:
        print(f">> {path.name}")
        result = process(path, args.check)
        results.append(result)
        if result["status"] == "updated":
            print(f"   {result['from']} -> {result['to']}  ({result['repo']})")
        elif result["status"] == "outdated":
            print(f"   would update {result['from']} -> {result['to']}  ({result['repo']})")
        elif result["status"] == "current":
            print(f"   up to date at {result['tag']}  ({result['repo']})")
        else:
            print(f"   skipped: {result['reason']}")

    # Machine-readable summary for the calling script.
    print("---RESULT---")
    print(json.dumps(results))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
