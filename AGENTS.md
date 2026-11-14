# AGENTS.md — bazixv13 Apps Flatpak repository

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
- The repo IS GPG-signed, and it must stay that way. `flatpakrepo` carries a
  `GPGKey=` field; without it Flatpak registers the remote `no-gpg-verify` and
  every **system-scope** install fails with
  `Can't pull from untrusted non-gpg verified remote`.
- Signing covers four commits, not just the summary: each app commit, the
  `appstream/x86_64` and `appstream2/x86_64` commits, and the summary itself.
  An unsigned appstream commit makes `flatpak update --appstream` fail, which
  is why Bazaar cannot list the apps.
- Never hand-edit `flatpakrepo`. Regenerate it with
  `scripts/make-flatpakrepo.sh` so `GPGKey=` always matches the signing key.
- The signing key lives in `$GPG_HOMEDIR` (default
  `~/.config/flatpak-repo-gpg`) and is never committed. Only the public key
  (`repo-key.asc`) and the base64 copy inside `flatpakrepo` are published.
  Recreate it with `scripts/init-signing-key.sh`.
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
   curl -fsSL https://bazixv13.github.io/flatpak-repo/flatpakrepo
   flatpak --user remote-ls bazixv13-apps   # after adding the remote
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
`flatpakrepo`, `.nojekyll`, `index.html` and `logo.svg`), commits, and pushes.
GitHub Pages then serves the new repo at
`https://bazixv13.github.io/flatpak-repo/`.

The remote name is **`bazixv13-apps`**:

```bash
flatpak remote-add --if-not-exists --from bazixv13-apps \
  https://bazixv13.github.io/flatpak-repo/flatpakrepo
```

(Note the argument order: `--from <remote-name> <flatpakrepo-url>`.)

## Troubleshooting

- `Flatpak system operation ConfigureRemote not allowed for user`: use
  `flatpak --user ...` for user installs, or `sudo -A` for system installs
  (follow the workspace AGENTS.md sudo/askpass rule).
- `Can't load file <name>`: the `--from` arguments are swapped; the remote name
  comes first, the flatpakrepo URL second.
- `remote-ls` is empty: confirm `summary` exists on `gh-pages` and the Pages
  build succeeded (`gh api /repos/bazixv13/flatpak-repo/pages`).
- After a repo rename the Pages URL changes; old `flatpakrepo` URLs 404 until
  remotes are re-added.
- Build failures usually mean the SDK/runtime version in the manifest is not on
  Flathub. Adjust `runtime-version`/`sdk` and retry.
