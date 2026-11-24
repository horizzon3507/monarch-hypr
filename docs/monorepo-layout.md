# Monorepo layout

One repository holds the whole distribution. Each part keeps the history it had before the import.

| Path | What it is | Origin |
| --- | --- | --- |
| `/` (`install/`, `bin/`, `config/`, `default/`, `test/`) | Desktop runtime, installed to `/usr/share/monarch` | monarch-os/monarch |
| `iso/` | Live ISO builder, installer orchestrator, VM and boot tests | monarch-os/monarch-iso, via monarch-hypr-iso |
| `pkgs/pkgbuilds/monarch/` | The `monarch` package recipe | monarch-os/monarch-pkgs (this one recipe only) |
| `.github/workflows/build-iso.yml` | Manual ISO build and QEMU boot check | monarch-hypr-iso |

## Build

```bash
cd iso
./bin/monarch-iso-make --local-source .. ../pkgs
```

`--local-source` mounts the repository root as the runtime source and `pkgs/` as the recipe tree, so the ISO is built from one commit. The package source copy leaves out `iso/` and `pkgs/`. The `archiso` submodule lives at `iso/archiso` (`git submodule update --init`).

## History

The `iso/` and `pkgs/pkgbuilds/monarch/` imports are `git subtree` merges without squash. Use `git log --follow <path>` to see the original commits; they appear under their old paths. The old `monarch-hypr-iso` repository is kept as is and is no longer updated.

## Not covered

Other upstream packages (`monarch-welcome`, `monarch-nvim`, the keyring) are not built here. The ISO installs them from the upstream repository.
