#!/bin/bash
# Static inspection of a built ISO: kernel, desktop packages, installer package lists.
# usage: inspect-iso.sh <iso> <outdir>   (needs xorriso, squashfs-tools)
set -euo pipefail
ISO=$1 OUT=$2; mkdir -p "$OUT"
sudo apt-get install -y -qq xorriso squashfs-tools >/dev/null
xorriso -osirrox on -indev "$ISO" -extract /arch/x86_64/airootfs.sfs "$OUT/airootfs.sfs" >/dev/null 2>&1
unsquashfs -d "$OUT/root" -f "$OUT/airootfs.sfs" usr/lib/modules usr/share/monarch-iso var/lib/pacman/local >/dev/null 2>&1 || true
ls "$OUT/root/usr/lib/modules" > "$OUT/module-dirs.txt" 2>/dev/null || true
ls "$OUT/root/var/lib/pacman/local" > "$OUT/live-packages.txt" 2>/dev/null || true
echo "kernel module dirs:"; cat "$OUT/module-dirs.txt"
echo "relevant packages in live root:"; grep -E '^(linux-cachyos|niri|noctalia|hyprland|waybar|walker|mako|hyprlock|uwsm|sddm)' "$OUT/live-packages.txt" || echo none
for f in monarch-base.packages monarch-other.packages; do
  echo "== $f"; grep -nE 'niri|noctalia|hyprland|waybar|walker|mako|hyprlock' "$OUT/root/usr/share/monarch-iso/$f" || echo "no desktop entries"
done
rm -f "$OUT/airootfs.sfs"
