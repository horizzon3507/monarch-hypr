# Fork status

What is proven and what is not. Update this file when a claim changes.

| Area | State |
| --- | --- |
| Source imported with upstream history | Done: desktop, `iso/` and `pkgs/pkgbuilds/monarch` in one repository |
| Hyprland as default desktop | In progress on the `hyprland-desktop` branch, not on `dev`. On a free CI runner (virtual GPU, Hyprland 0.57.2, Quickshell 0.3.2) the full Lua config loaded with 171 binds and no errors, and the Quickshell bar mapped, reserved space and answered a real pointer click. Not run on an installed system, not on real hardware |
| Quickshell panels (network, theme, display, background, crash history, first steps, usage) | Merged panels were run on real Quickshell in a headless sway with stubbed system commands, not on Hyprland and not against real NetworkManager, CodexBar or installers. Keyboard capture and release after the close button were measured on real Hyprland for the Wi-Fi QR panel only. Escape does not close a panel reliably |
| Fingerprint login on the lock screen | Known gap: the Noctalia lock screen managed it; hyprlock has no equivalent set up here. Fingerprint setup rows are unavailable on Hyprland until a lock-screen design exists |
| linux-cachyos kernel | Inherited from upstream, not re-verified here |
| ISO build in CI | Proven for the unmodified upstream Niri/Noctalia ISO only (run 45439396855 in the archived `monarch-hypr-iso` repo). Not proven for this fork's tree |
| ISO boots in a VM | The upstream ISO and one intermediate build of this fork (`hyprland-desktop` at 106c2e1, which still ships Noctalia) reached the installer welcome screen in UEFI and BIOS. No install was completed, no installed system was rebooted, and no desktop screenshot of this fork exists yet |

A bootable ISO is only claimed after a VM boot log or screenshot exists for that build.

## Functional-loss inventory: Noctalia and Niri to Hyprland and Quickshell

Install scope: fresh installs only. An old Niri/Noctalia home is refused by `monarch-reconcile`. Evidence levels: stub, headless sway, real Hyprland runner, installed system. Nothing here is claimed as parity until the last column says so.

| Former feature | Now | Status |
| --- | --- | --- |
| Network, Wi-Fi QR, display, theme, background, crash, first-steps, usage panels | Quickshell panels | Replaced. Stub or headless-sway evidence only |
| Bar: workspaces, clock, tray, network, brightness, volume, battery | Quickshell bar | Replaced. Bar, clock, workspaces, ethernet and volume were seen on the installed intermediate ISO |
| Recording, caffeine, DND, night light and update-available bar chips | Quickshell state chips (PR #69) | Replaced once merged. Stub and headless-sway evidence only |
| Voxtype bar indicator | None | Known gap |
| Bluetooth chip, privacy dot, control center | None | Known gap (verify against the bar before release) |
| Todo, LazyVPN and PentestEnv shortcuts and bar items | None. Packages and menu entries stay, helpers only run package setup | Known gap, no new panel planned |
| Herdr, Neovim, Obsidian and Helix generated themes | Default theme of each tool | Documented fallback |
| Fingerprint on the lock screen | None. Setup rows stay gated, no PAM change | Known gap |
| Upgrade from an old Niri/Noctalia install | None | Dropped by decision, reinstall to switch |
| Vendored community templates (UNKNOWN license) | Removed | Must not ship |
