# AGENTS.md — Hideaway Flatpak repository

This repository publishes a **single Flatpak remote** for Hideaway and the
maintainer's other apps. Read this before changing anything.

## Golden rules

- **Never** commit `repo/`, `build/`, or `.flatpak-builder/` — they are local
  scratch and are git-ignored.
- The published remote lives on the **`gh-pages`** branch only. Do not put the
  OSTree blobs on `main`.
- The app manifest list is the source of truth: one JSON file per app in
  `apps/`.
- Keep `.nojekyll`, `flatpakrepo`, `index.html` and `logo.svg` at the root of
  `gh-pages`. `flatpakrepo` and `.nojekyll` are required for the remote to work;
  `index.html` and `logo.svg` are the landing page and the icon referenced by
  `flatpakrepo`. `publish.sh` copies all four back after syncing.
- The repo is unsigned. Do not add a `GPGKey` unless the user explicitly asks
  for signing.
- Do not touch the `gh-pages` branch of the separate `hideaway` repo (the old
  Pages deployment stays in place for now).

## Prerequisites

`flatpak`, `flatpak-builder`, `ostree`, `git`, `rsync`, `python3`.

`flatpak-builder` installs the runtime/SDK named in the manifest on first build
(needs network access).

## Add an app

1. Create `apps/<app-id>.json` from the app's upstream manifest.
   - Required key: `app-id`.
   - Optional key: `branch` (default `master`).
   - Sources must be reproducible (git tag/commit, or archive with `sha256`).
2. Run:

   ```bash
   ./scripts/sync-repo.sh
   ./scripts/add-app.sh apps/<app-id>.json
   ./scripts/publish.sh
   ```

3. Verify:

   ```bash
   ./scripts/list-apps.sh
   curl -fsSL https://bazixv13.github.io/hideaway-flatpak/flatpakrepo
   flatpak --user remote-ls hideaway    # after adding the remote
   ```

## Remove an app

```bash
./scripts/sync-repo.sh
./scripts/remove-app.sh <app-id>
./scripts/publish.sh
```

`remove-app.sh` deletes the refs and rebuilds the summary. Objects stay on disk
until `ostree --repo=repo prune --refs-only`.

## How publishing works

`publish.sh` clones `gh-pages`, rsyncs the local `repo/` over it (preserving
`flatpakrepo` and `.nojekyll`), commits, and pushes. GitHub Pages then serves
the new repo at `https://bazixv13.github.io/hideaway-flatpak/`.

## Troubleshooting

- `Flatpak system operation ConfigureRemote not allowed for user`: use
  `flatpak --user ...` for user installs, or `sudo -A` for system installs
  (follow the workspace AGENTS.md sudo/askpass rule).
- `remote-ls` is empty: confirm `summary` exists on `gh-pages` and the Pages
  build succeeded (`gh api /repos/bazixv13/hideaway-flatpak/pages`).
- A 404 on the site root is expected; test `/flatpakrepo` instead.
- Build failures usually mean the SDK/runtime version in the manifest is not on
  Flathub. Adjust `runtime-version`/`sdk` and retry.
