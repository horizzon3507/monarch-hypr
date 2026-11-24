# monarch-hypr

> **Fork notice.** monarch-hypr is an independent fork of [monarch-os/monarch](https://github.com/monarch-os/monarch) (MIT). It is replacing the Niri + Noctalia desktop with a customized Hyprland desktop and keeps the CachyOS base. It is not affiliated with or endorsed by the upstream project. The `upstream-base` branch holds the unmodified upstream history this fork started from. See [CREDITS.md](CREDITS.md).
>
> **Status.** Work in progress. No bootable ISO is published yet; see [docs/fork-status.md](docs/fork-status.md).

# Monarch

[![Documentation](https://img.shields.io/badge/Documentation-Read_the_docs-7e33ff?style=flat-square)](https://docs.monarchlinux.com/)
[![CI](https://img.shields.io/github/actions/workflow/status/monarch-os/monarch/ci.yml?branch=dev&label=CI&style=flat-square)](https://github.com/monarch-os/monarch/actions/workflows/ci.yml?query=branch%3Adev)

Monarch turns a fresh [CachyOS](https://cachyos.org) installation into a fully-configured, beautiful, and modern desktop. It is lightly opinionated: a good default setup that stays easy to change. It also carries some security tooling and shell helpers inherited from [SkillArch](https://github.com/laluka/SkillArch).

## This fork: what exists today

This repository is a work in progress. The goal is a lightly opinionated desktop in the spirit of Omarchy: a good default setup that stays easy to change, on CachyOS with Hyprland.

- **Compositor**: [Hyprland](https://hyprland.org), configured in Lua. It is the default on the `hyprland-desktop` branch, not yet on `dev`.
- **Desktop shell**: a small custom [Quickshell](https://quickshell.org) shell (bar and panels for network, theme, display, background, crash history, first steps and agent usage). The lock screen, idle handling, notifications, launcher and on-screen displays stay on hyprlock, hypridle, mako, Walker and swayosd.
- **Noctalia and Niri** are still shipped while the retirement is staged. They are going away in later changes, so do not build on them.

Not done yet, and not claimed: a published or validated ISO release (intermediate CI builds of this fork have booted to the installer in a VM, see the status page), a completed install, a reboot into the desktop, fingerprint login on the lock screen, and any run on real hardware. [docs/fork-status.md](docs/fork-status.md) lists what has been run and where, and is the source of truth when this page and it disagree.

### Trying it

There is no supported install path for this fork yet. The ISO and installer links of the upstream project (documentation site, nightly ISO) install the upstream Niri and Noctalia desktop, not this one. To follow progress or contribute, read [docs/fork-status.md](docs/fork-status.md) and [docs/development.md](docs/development.md).

Monarch is an independently maintained **hard fork** of [Omarchy](https://omarchy.org). The `monarch` CLI and the install scripts descend from it, and a good number of commands are still Omarchy's unchanged but for the name. The stack has diverged (CachyOS rather than Arch, and a Hyprland-based desktop with its own shell), but the lineage is Omarchy's, and so is the licence. It also carries some security tooling and shell helpers inherited from [SkillArch](https://github.com/laluka/SkillArch).

## The true monarchs

Monarch is, first and foremost, an assembly of projects built and maintained by others. Its role is to bring them together into a cohesive desktop environment, with the inherited security tooling — not to take credit for their work. The people and communities behind those projects are the true sovereigns:

- [Noctalia](https://github.com/noctalia-dev/noctalia) — the desktop shell that brings the interface to life, from the bar and launcher to notifications and theming.
- [Niri](https://github.com/YaLTeR/niri) — the scrollable-tiling Wayland compositor at the heart of the desktop.
- [SkillArch](https://github.com/laluka/SkillArch) — the inspiration for Monarch's cybersecurity workflows, tools, and shell helpers.
- [Exegol](https://github.com/ThePorgs/Exegol) — the source of inspiration for several of Monarch's cybersecurity aliases.
- [Omarchy](https://omarchy.org) — the original foundation of Monarch's installer, CLI, and many everyday commands.
- [CachyOS](https://cachyos.org) and [Arch Linux](https://archlinux.org) — the distribution foundations and package ecosystem that make it all possible.

And to the many other upstream projects, maintainers, and contributors whose work makes this environment possible: thank you. The crown belongs to you.

## Contributing

Contributions are welcome — bug reports, ideas, documentation, translations, and code all help make Monarch better.

- Check the [existing issues](https://github.com/monarch-os/monarch/issues) before reporting a bug or suggesting a feature. Include your setup, steps to reproduce, and relevant logs when reporting a problem.
- For larger changes, open an issue first so we can discuss the approach before you invest time in an implementation.
- Keep pull requests focused, follow the repository's [development guidance](AGENTS.md), and describe what changed and how you tested it. Include screenshots for visual changes.
- When a problem belongs to an upstream project, help improve it there too — Monarch benefits when its foundations get better.

## License

Monarch is released under the [MIT License](https://opensource.org/licenses/MIT), inherited from Omarchy.
