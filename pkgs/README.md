# pkgs

Package recipes built into the ISO. Only the `monarch` runtime recipe is kept here, imported with its history from [monarch-os/monarch-pkgs](https://github.com/monarch-os/monarch-pkgs) (MIT, see `LICENSE`). Every other `monarch-*` package still comes from the upstream package repository configured in `iso/configs/pacman-online.conf`.

Build with the repository root as the runtime source: `cd iso && ./bin/monarch-iso-make --local-source .. ../pkgs`.
