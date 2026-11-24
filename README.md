# bazixv13 Apps — Flatpak repository

A single Flatpak remote that hosts [Hideaway](https://github.com/bazixv13/hideaway)
and other apps by [@bazixv13](https://github.com/bazixv13).

Published at **https://bazixv13.github.io/flatpak-repo/**
(GitHub Pages, `gh-pages` branch).

## Add the remote

```bash
flatpak remote-add --if-not-exists --from bazixv13-apps https://bazixv13.github.io/flatpak-repo/flatpakrepo
```

Then install any app it provides:

```bash
flatpak install bazixv13-apps io.github.bazixv13.Hideaway
```

Every app also has a one-click install file at the site root,
`<app-id>.<branch>.flatpakref`, which GNOME Software and Bazaar can open
directly: it carries the URL and the key, so no terminal is involved. For
example
`https://bazixv13.github.io/flatpak-repo/io.github.localsend_adwaita.LocalSend.stable.flatpakref`.

List what is available:

```bash
flatpak remote-ls bazixv13-apps
```

### Beta builds

Apps that ship pre-releases also publish a `beta` branch. It is a separate
branch, so installing it never moves stable users onto a beta:

```bash
flatpak install bazixv13-apps io.github.localsend_adwaita.LocalSend//beta
```

Anything published to `stable` (or the app's own branch) only follows tags
like `v0.3.50`; the beta channel follows tags like `v0.3.53-beta`.

## Repository layout

| Branch     | Contents |
|------------|----------|
| `main`     | Tooling, app manifests, docs (this branch) |
| `gh-pages` | The published OSTree repo served by GitHub Pages |

```
apps/                  Flatpak manifests, one file per app and channel
scripts/
  sync-repo.sh         Download the published repo into ./repo
  add-app.sh           Build a manifest and export it into ./repo
  remove-app.sh        Remove an app from ./repo
  list-apps.sh         List apps in ./repo
  publish.sh           Push ./repo to gh-pages
  make-flatpakrefs.sh  Write the one-click install files for the site root
  update_manifests.py  Move manifests to the newest upstream tag
  check-key-expiry.sh  Fail if the signing key is expired or expiring
flatpakrepo            Remote descriptor served at the site root
lint-exceptions.json   flatpak-builder-lint findings that are by design here
index.html             Landing page with the add-remote instructions
logo.svg               Repo icon referenced by flatpakrepo
.nojekyll              Lets GitHub Pages serve files without index.html
```

`repo/`, `build/` and `.flatpak-builder/` are local scratch directories and are
git-ignored.

## Add an app

1. Put the Flatpak manifest in `apps/<app-id>.json`.
   - `app-id` is required.
   - `branch` is optional (defaults to `master`). A manifest with
     `"branch": "beta"` is the test channel: it follows pre-release tags
     (`0.3.53-beta`) instead of the newest release. Name its file
     `apps/<app-id>.beta.json` so both channels can coexist.
   - An app that vendors crates lists its dependency list as a local source
     (`"sources": ["<name>.cargo-sources.json", ...]`). The updater downloads
     that app's `flatpak/cargo-sources.json` from the new tag and writes it
     beside the manifest, so each release builds with its own dependency list.
     It has to be a local file: flatpak-builder only expands the sources from a
     JSON file it finds on disk, not one downloaded mid-build.
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
- `io.github.localsend_adwaita.LocalSend` — LocalSend, `stable` from
  `apps/*.json` and `beta` from `apps/*.beta.json`.
- `com.github.kali.Hideaway` — legacy app id still present in the published
  repo. Kept on purpose; remove it only if asked.

## Notes

- The repo publishes **static deltas**, so an update downloads only what
  changed instead of the whole app commit, and `build-update-repo --prune`
  drops the appstream commits each publish replaces.
- `flatpakrepo` names Flathub in `RuntimeRepo=`, so a user who never added
  Flathub is prompted for `org.gnome.Platform` instead of being told the
  runtime is missing.
- The repo is **GPG-signed**. `flatpakrepo` embeds the public key as `GPGKey=`,
  so Flatpak adds the remote with verification ON. This matters: an unsigned
  remote is registered `no-gpg-verify`, and Flatpak then refuses to pull it as
  root (`Can't pull from untrusted non-gpg verified remote`), so system-scope
  installs break.
- Signing covers the app commits, the `appstream`/`appstream2` commits and the
  summary. The appstream commits matter for discovery: if they are unsigned,
  `flatpak update --appstream` fails and app stores such as Bazaar cannot list
  the apps.
- The signing key is local (`~/.config/flatpak-repo-gpg`) and never committed.
  Only the public key (`repo-key.asc`) and the base64 copy in `flatpakrepo` are
  published. `scripts/init-signing-key.sh` creates it;
  `scripts/make-flatpakrepo.sh` regenerates the descriptor.
- GitHub Pages must serve the `flatpakrepo` file and the OSTree objects; the
  `.nojekyll` file is required because Jekyll would otherwise hide dotfiles.
- The site root serves the landing page (`index.html`); the `flatpakrepo` file
  is what `flatpak remote-add --from` downloads.
- Updates are applied by the `Update apps` workflow: every six hours, on a
  `repository_dispatch` of type `upstream-release` from an app repo, or by hand.
  Both app repos send one on every `v*` tag: `bazixv13/localsend-adwaita`
  (`build.yml`, after it uploads the release) and `bazixv13/hideaway`
  (`dispatch-flatpak.yml`). Only the payload's `tag` is used, and only to label
  the run; which manifests need rebuilding is decided by re-reading upstream
  tags with `git ls-remote`, so a dispatch cannot pin a bogus version.
- That dispatch needs a token which can write to this repository, stored as
  `FLATPAK_REPO_TOKEN` in the app repo's secrets (`GITHUB_TOKEN` cannot reach
  across repositories): a classic token with `repo`, or a fine-grained token
  with *Contents: read and write* here. What a missing or revoked token breaks
  differs by app repo, by design: LocalSend logs
  `FLATPAK_REPO_TOKEN is not set; ...` and exits 0, so the release still reaches
  users on the next scheduled run, up to six hours late; Hideaway fails the
  job, so the delay is a red run instead of a release that looks published. No
  tag is lost either way — the scheduled run re-reads upstream tags — but until
  that run, nothing here knows the release happened.
- Only the manifests whose tag moved are rebuilt, and a beta tag never touches
  the stable branch.
- The `Verify published repo` workflow re-checks the published `gh-pages` branch
  once a day: summary entries must match real refs, every commit must be signed
  and carry an array ref binding (a string binding is accepted by root but
  rejected by flatpak's system helper, which is how `flatpak update --appstream`
  breaks silently for system installations), every app ref must have its
  `.flatpakref`, the pinned archive checksums must still match upstream (GitHub
  regenerates tag tarballs, so a rewritten tag silently breaks the next build),
  and the signing key must not be expired or expire within 30 days. A red run
  is the alert. The same workflow lints the manifests with
  `flatpak-builder-lint`; findings that are by design here — the `branch`
  property is how the beta channel is routed, and LocalSend's app id does not
  follow the reverse-DNS-of-a-GitHub-repo shape the checks assume — are listed
  in `lint-exceptions.json`. `Update apps` lints before it builds.
