#!/bin/bash
# Static inspection of a built ISO. Prints findings; fails only on the gates the
# commit under test claims, so an intermediate ISO is not held to final claims.
# usage: inspect-iso.sh <iso> <outdir>
#   INSPECT_EXPECT_PRESENT="linux-cachyos hyprland"   packages that must be in the live root
#   INSPECT_EXPECT_ABSENT="niri noctalia"             packages that must NOT be in the live root,
#                                                      the installer package lists or the monarch package deps
# Without either variable nothing is gated (report only).
set -euo pipefail
ISO=$1 OUT=$2; mkdir -p "$OUT"
sudo apt-get install -y -qq xorriso squashfs-tools >/dev/null
xorriso -osirrox on -indev "$ISO" -extract /arch/x86_64/airootfs.sfs "$OUT/airootfs.sfs" >/dev/null 2>&1
unsquashfs -d "$OUT/root" -f "$OUT/airootfs.sfs" usr/lib/modules usr/share/monarch-iso var/lib/pacman/local >/dev/null 2>&1 || true
rm -f "$OUT/airootfs.sfs"
ls "$OUT/root/usr/lib/modules" > "$OUT/module-dirs.txt" 2>/dev/null || true
# package names from pacman local db dir names (name-version-rel)
ls "$OUT/root/var/lib/pacman/local" 2>/dev/null | sed -E 's/-[^-]+-[^-]+$//' | sort -u > "$OUT/live-packages.txt" || true
cat "$OUT"/root/usr/share/monarch-iso/*.packages 2>/dev/null | sed 's/#.*//' | tr -s ' \t' '\n' | sed '/^$/d' | sort -u > "$OUT/installer-packages.txt" || true
# depends of the monarch package that went into the ISO
desc=$(ls -d "$OUT"/root/var/lib/pacman/local/monarch-[0-9]* 2>/dev/null | head -n1 || true)
[[ -n $desc && -f $desc/desc ]] && sed -n '/^%DEPENDS%/,/^$/p' "$desc/desc" | sed '1d;/^$/d' | sed -E 's/[<>=].*//' | sort -u > "$OUT/monarch-depends.txt" || : > "$OUT/monarch-depends.txt"

{
echo "kernel module dirs:"; cat "$OUT/module-dirs.txt"
for k in linux-cachyos niri noctalia hyprland quickshell waybar walker mako hyprlock uwsm sddm; do
  printf '%-14s live:%s installer-list:%s monarch-depends:%s\n' "$k" \
    "$(grep -qx "$k" "$OUT/live-packages.txt" && echo yes || echo no)" \
    "$(grep -qx "$k" "$OUT/installer-packages.txt" && echo yes || echo no)" \
    "$(grep -qx "$k" "$OUT/monarch-depends.txt" && echo yes || echo no)"
done
} | tee "$OUT/report.txt"

rc=0
for p in ${INSPECT_EXPECT_PRESENT:-}; do
  grep -qx "$p" "$OUT/live-packages.txt" || grep -qx "$p" "$OUT/installer-packages.txt" || { echo "GATE FAIL: $p expected present"; rc=1; }
done
for p in ${INSPECT_EXPECT_ABSENT:-}; do
  for f in live-packages installer-packages monarch-depends; do
    ! grep -qx "$p" "$OUT/$f.txt" || { echo "GATE FAIL: $p expected absent but found in $f"; rc=1; }
  done
done
[[ -s $OUT/module-dirs.txt ]] || { echo "GATE FAIL: no kernel modules found in live root"; rc=1; }
exit $rc
