# Fork architecture notes

Map of where the upstream Niri + Noctalia desktop is wired in, so the Hyprland swap has a checklist. Counts come from `grep -rli` over the upstream tree at fork time (files mentioning the word, not lines).

## Layers

1. Packages: `install/monarch-base.packages` lists `niri`, `noctalia`, `sddm` and `uwsm`.
2. Login: `install/login/sddm.sh` writes `/etc/sddm.conf.d/10-wayland.conf` with `CompositorCommand=niri --config /usr/share/sddm/niri.kdl`, using `default/sddm/niri.kdl`. A Hyprland session needs a different greeter compositor or an SDDM setup that does not depend on Niri.
3. Session environment: `config/uwsm/default` and `config/uwsm/env`.
4. Compositor config: `config/niri/` (`user.kdl`, `noctalia.kdl`, `workspaces.conf`). `config/niri/user.kdl` holds the keybinds and window rules that need a Hyprland equivalent. There is no `config/hypr/` yet.
5. Shell: `config/noctalia/` (`config.toml`, widgets, workspaces, palettes, templates). Noctalia provides the bar, launcher, notifications, control center, lock screen, OSD, wallpaper and theming.
6. Commands: `bin/monarch-*`. Niri is referenced in 44 files (for example `monarch-niri-*`, `monarch-restart-niri`, `monarch-refresh-niri`, `monarch-capture-*`, `monarch-display-*`, `monarch-launch-or-focus`, `monarch-system-lock`). Noctalia is referenced in more than 40 command files (theme, menu, toggle, display, audio and install commands).
7. Reconciliation: `install/reconcile/` has Noctalia activation, plugin and template scripts and a `schema/1-to-2/` migration. `install/user/niri.sh` and `install/user/first-run/enable-noctalia-plugins.sh` run per user.
8. Tests: `test/` has 34 files mentioning Niri. CI runs `test/run integration`, a package availability check and shellcheck.

## Counts by directory (files mentioning niri)

bin 44, test 34, default 18, install 15, config 4, docs 3, etc 2, themes 1, agents 1, README 1. Files mentioning noctalia: 239 in total. Files mentioning hypr: 15.

## ISO side

`monarch-hypr-iso` builds a CachyOS live ISO with archiso inside a `cachyos/cachyos:latest` container (`bin/monarch-iso-make`, `builder/build-iso.sh`). `configs/airootfs/usr/local/bin/monarch-iso-install` and `configs/airootfs/usr/share/monarch-iso/orchestrator/` hold the installer flow that runs archinstall and then the Monarch installer in the target. Boot menus are in `configs/grub/` and `configs/syslinux/`. archiso is a git submodule.

## Open questions for the Hyprland work

- Which tools replace each Noctalia surface (bar, launcher, notifications, lock, wallpaper, OSD, theming).
- How `monarch-*` commands that call `noctalia msg` or `niri msg` map to `hyprctl` and the chosen tools.
- How the SDDM greeter starts without Niri.
