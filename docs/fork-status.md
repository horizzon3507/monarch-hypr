# Fork status

What is proven and what is not. Update this file when a claim changes.

| Area | State |
| --- | --- |
| Source imported with upstream history | Done: desktop, `iso/` and `pkgs/pkgbuilds/monarch` in one repository |
| Hyprland as default desktop | In progress on the `hyprland-desktop` branch, not on `dev`. On a free CI runner (virtual GPU, Hyprland 0.57.2, Quickshell 0.3.2) the full Lua config loaded with 171 binds and no errors, and the Quickshell bar mapped, reserved space and answered a real pointer click. Also seen on an installed system in a QEMU VM (see the ISO rows). Not run on real hardware |
| Quickshell panels (network, theme, display, background, crash history, first steps, usage) | Merged panels were run on real Quickshell in a headless sway with stubbed system commands, not on Hyprland and not against real NetworkManager, CodexBar or installers. Keyboard capture and release after the close button were measured on real Hyprland for the Wi-Fi QR panel only. Escape closed the theme panel on the installed VM (one run); behavior on other panels is unchecked |
| Fingerprint login on the lock screen | Known gap: the Noctalia lock screen managed it; hyprlock has no equivalent set up here. Fingerprint setup rows are unavailable on Hyprland until a lock-screen design exists |
| linux-cachyos kernel | Inherited from upstream, not re-verified here |
| ISO build in CI | Build ISO run 45530622089 on this fork's `hyprland-desktop` at 7bb4fcf: the build and package inspection passed (retired Niri/Noctalia packages absent; linux-cachyos, hyprland and quickshell present). The earlier candidate b0dfa44 also built. Its boot-test job also passed (QEMU boot steps, see the run). Checksum and download of the ISO are not recorded here, and no public release exists |
| ISO install and boot in a VM | Installer probe run 45533133462 on the ISO from run 45530622089 (7bb4fcf), offline and online jobs both passed in QEMU: fresh install, reboot into the installed system, graphical login, no failed units, no Niri/Noctalia packages installed. A real Hyprland session showed the wallpaper before and after `monarch restart shell`, and the lock screen, by screenshot. Test VM with a disposable account and a virtual GPU only. Not tested on real hardware, not a release |
| ISO build and probe on 8da334c | Build ISO run 45628700765 passed (all jobs) and install probe run 45632524498 passed offline and online in a QEMU VM with a virtual GPU: wallpaper before and after a shell restart, Obsidian service and installed-path checks. The installed journal carries a package-skew warning: Quickshell 0.3.2-1 (Arch `extra`, built 2026-10-08 against Qt 6.12.0) runs on Qt 6.12.1-1 (`qt6-base`, `qt6-declarative`), and Quickshell says this is likely to cause crashes and needs a rebuild. No crash was seen in that run. The earlier ISO from 7bb4fcf had Qt 6.12.0 and no warning. The packages come from the Arch repositories, not from this repo, so the fix is a Quickshell rebuild upstream; nothing is pinned or downgraded here. Checked 2026-11-25: Arch `extra` still lists quickshell 0.3.2-1 from 2026-10-08 and qt6-base 6.12.1-1. Lid-close lock and the Helix/Obsidian wiring have stub or service-level evidence only |

A bootable ISO is only claimed after a VM boot log or screenshot exists for that build.

## Functional-loss inventory: Noctalia and Niri to Hyprland and Quickshell

Install scope: fresh installs only. An old Niri/Noctalia home is refused by `monarch-reconcile`. Evidence levels: stub, headless sway, real Hyprland runner, installed system. Nothing here is claimed as parity until the last column says so.

| Former feature | Now | Status |
| --- | --- | --- |
| Network, Wi-Fi QR, display, theme, background, crash, first-steps, usage panels | Quickshell panels | Replaced. Stub or headless-sway evidence only |
| Bar: workspaces, clock, tray, network, brightness, volume, battery | Quickshell bar | Replaced. Bar, clock, workspaces, ethernet and volume were seen on the installed intermediate ISO |
| Recording, caffeine, DND, night light and update-available bar chips | Quickshell state chips | Replaced. Night light was toggled on an installed VM: process, IPC and chip agree and the status JSON reads true then false with exit 0. No colour measurement. The other chips have stub and headless-sway evidence only |
| Voxtype bar indicator | None | Known gap |
| Bluetooth chip, privacy dot, control center | None | Known gap (verify against the bar before release) |
| Todo, LazyVPN and PentestEnv shortcuts and bar items | None. Packages and menu entries stay, helpers only run package setup | Known gap, no new panel planned |
| Wallpaper | Quickshell background layer reading `~/.config/monarch/current/wallpaper.json`; `monarch wallpaper set` publishes it | Replaced. hyprpaper segfaulted in the QEMU VM (buffer allocation failed, upstream hyprwm/hyprpaper#343) and was removed. Wallpaper pixels seen on the installed VM before and after a shell restart. Real GPU unproven |
| Helix and Obsidian generated themes | Rendered Monarch theme files linked by `monarch-install-helix` and `monarch-obsidian-theme` (not shipped in the ISO; installed at probe time). Probe run 45636942353 (same ISO as 8da334c, both jobs passed): the rendered CSS and TOML have resolved colours and no placeholders. Helix, inspected by screenshot: the custom theme was applied (dark with purple, syntax colours visible). Obsidian: installed, but it exited with no visible window and the cause is unknown, so the Obsidian theme is INCONCLUSIVE; the service and symlink checks passing does not show that Obsidian uses the theme | Helix: seen once in a VM. Obsidian: not verified |
| Herdr and Neovim generated themes | Default theme of each tool | Documented fallback |
| Fingerprint on the lock screen | None. Setup rows stay gated, no PAM change | Known gap |
| Upgrade from an old Niri/Noctalia install | None | Dropped by decision, reinstall to switch |
| Vendored community templates (UNKNOWN license) | Removed | Must not ship |
