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
