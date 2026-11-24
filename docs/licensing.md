# Licensing inventory

This file records what is known about the licenses of what this repository ships. It does not clear anything. "Unknown" means no license or origin is recorded in the repository, not that the item is unlicensed. "Inference" marks a guess that has not been checked against the source.

The PKGBUILD at `pkgs/pkgbuilds/monarch/PKGBUILD` declares `license=('MIT' 'LicenseRef-unknown')`. Nothing in the repository explains the second entry. The most likely reason (inference) is the bundled non-code assets below. This file does not change that declaration.

## Code

| Part | Notice | State |
| --- | --- | --- |
| Repository root (desktop runtime) | `LICENSE`, MIT, "Copyright (c) David Heinemeier Hansson" | Known. Inherited from Omarchy through the upstream monarch repository. Kept unchanged |
| `iso/` | `iso/LICENSE`, MIT, "Copyright (c) 2025 Anton Hvornum" | Known. Kept unchanged |
| `pkgs/` | `pkgs/LICENSE`, MIT, same text as the root notice | Known. Kept unchanged |
| Changes by this fork | No separate notice yet | Unknown. Treat as covered by the MIT notices above until the user decides otherwise |

See `CREDITS.md` for attribution.

## Bundled non-code assets

| Area | What is there | State |
| --- | --- | --- |
| `themes/` images | 110 PNG, JPG and WEBP files (wallpapers and previews) across 22 theme directories | Unknown origin and license. No per-theme LICENSE, NOTICE or COPYING file exists in the repository |
| `themes/` color schemes | Many are named after upstream palettes (for example catppuccin, nord, gruvbox, rose-pine, tokyo-night, kanagawa) | Inference only: those palettes are published by their own projects under their own licenses. Not checked here |
| `assets/` | `logo.png`, `demo.png`, `demo-preview.png`, `demo.gif` | Unknown for each file |
| `logo.svg`, `logo.txt`, `icon.png`, `icon.txt` | Project logo and icon files at the root | Unknown |
| Fonts | No font files are stored in the repository | Known. Fonts come in as packages |

## Configs derived from other projects

`default/` holds configs and defaults for tools such as alacritty, foot, ghostty, chromium, firefox, zsh, niri, noctalia, snapper and sddm. Whether any were copied from third-party projects, and under what license, is not recorded. State: unknown, except where a file carries its own header.

### Vendored Noctalia community templates

`default/noctalia/community-templates/` (neovim, obsidian, vscode, zed) is a copy of https://github.com/noctalia-dev/community-templates at revision 682506c (see `upstream.json`). At that revision the upstream repository has no license file, the GitHub API reports no license for it, and its README states none (checked 2026-11-24). State: unknown. No permission to redistribute is recorded, and `CREDITS.md` has no entry for it. Do not treat these files as MIT. They are scheduled to leave with the Noctalia retirement. New editor themes for the Quickshell shell are written from scratch and must not derive from them.

## Installed packages

`install/*.packages` lists about 240 package names (Arch, CachyOS and AUR). Each package has its own license, set by its packager. This repository does not inventory them, and no claim is made about them here. Packages the ISO pulls in follow the same rule.

## Reuse rules for new code

- Reuse is allowed only from MIT or equivalent sources, with the exact upstream notice kept in `CREDITS.md`.
- GPL code is not copied into this repository without a separate decision.
- A new asset needs its source and license written in this file in the same pull request.

## Open questions for the repository owner

1. Keep, replace or drop the theme wallpapers and the logo files whose origin is unknown.
2. Whether the fork's own changes should carry an extra copyright line.
3. Whether to publish the ISO before the table above has no "Unknown" rows for shipped assets.
