# Hideaway Flatpak repository

A single Flatpak remote that hosts [Hideaway](https://github.com/bazixv13/hideaway)
and other apps by [@bazixv13](https://github.com/bazixv13).

Published at **https://bazixv13.github.io/hideaway-flatpak/**
(GitHub Pages, `gh-pages` branch).

## Add the remote

```bash
flatpak remote-add --if-not-exists --from hideaway \
  https://bazixv13.github.io/hideaway-flatpak/flatpakrepo
```

Then install any app it provides:

```bash
flatpak install hideaway io.github.bazixv13.Hideaway
```

List what is available:

```bash
flatpak remote-ls hideaway
```

## Repository layout

| Branch     | Contents |
|------------|----------|
| `main`     | Tooling, app manifests, docs (this branch) |
| `gh-pages` | The published OSTree repo served by GitHub Pages |

```
apps/                  Flatpak manifests, one file per app
scripts/
  sync-repo.sh         Download the published repo into ./repo
  add-app.sh           Build a manifest and export it into ./repo
  remove-app.sh        Remove an app from ./repo
  list-apps.sh         List apps in ./repo
  publish.sh           Push ./repo to gh-pages
flatpakrepo            Remote descriptor served at the site root
index.html             Landing page with the add-remote instructions
logo.svg               Repo icon referenced by flatpakrepo
.nojekyll              Lets GitHub Pages serve files without index.html
```

`repo/`, `build/` and `.flatpak-builder/` are local scratch directories and are
git-ignored.

## Add an app

1. Put the Flatpak manifest in `apps/<app-id>.json`.
   - `app-id` is required.
   - `branch` is optional (defaults to `master`).
2. Sync the current published state, build and export:

   ```bash
   ./scripts/sync-repo.sh
   ./scripts/add-app.sh apps/<app-id>.json
   ```

3. Publish:

   ```bash
   ./scripts/publish.sh
   ```

## Remove an app

```bash
./scripts/sync-repo.sh
./scripts/remove-app.sh <app-id>
./scripts/publish.sh
```

## Current apps

- `io.github.bazixv13.Hideaway` — Hideaway, manifest in `apps/`.
- `com.github.kali.Hideaway` — legacy app id still present in the published
  repo. Kept on purpose; remove it only if asked.

## Notes

- The repo is **unsigned**, so Flatpak adds it with GPG verification disabled
  automatically (the descriptor has no `GPGKey`).
- GitHub Pages must serve the `flatpakrepo` file and the OSTree objects; the
  `.nojekyll` file is required because Jekyll would otherwise hide dotfiles.
- The site root serves the landing page (`index.html`); the `flatpakrepo` file
  is what `flatpak remote-add --from` downloads.
