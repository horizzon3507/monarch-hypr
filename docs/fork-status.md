# Fork status

What is proven and what is not. Update this file when a claim changes.

| Area | State |
| --- | --- |
| Source imported with upstream history | Done: desktop, `iso/` and `pkgs/pkgbuilds/monarch` in one repository |
| Hyprland as default desktop | In progress on the `hyprland-desktop` branch, not on `dev`. Its config passes the Hyprland 0.57.2 `--verify-config` parser only; the compositor has not been run |
| linux-cachyos kernel | Inherited from upstream, not re-verified here |
| ISO build in CI | Proven for the unmodified upstream Niri/Noctalia ISO only (run 45439396855 in the archived `monarch-hypr-iso` repo). Not proven for this fork's tree |
| ISO boots in a VM | The same upstream ISO reached the installer welcome screen in UEFI and BIOS. No install was completed and nothing customized has been booted |

A bootable ISO is only claimed after a VM boot log or screenshot exists for that build.
