#!/bin/bash
# Static inspection of a built ISO. Prints findings; fails only on the gates the
# commit under test claims, so an intermediate ISO is not held to final claims.
# usage: inspect-iso.sh <iso> <outdir>
#   INSPECT_EXPECT_PRESENT="linux-cachyos hyprland"  exact package names that must appear somewhere below
#   INSPECT_EXPECT_ABSENT="niri noctalia"            package FAMILIES (name or name-*) that must appear nowhere below
# Sets inspected (each written to <outdir>/<set>.txt, one package name per line):
#   live-root         pacman local db of the live system (airootfs.sfs)
#   installed-root    pacman -Q of the target image shipped as monarch-root.img.zst (root-image.packages)
#   installer-lists   /usr/share/monarch-iso/*.packages and /usr/share/monarch/install/*.packages
#   offline-mirror    package files in the offline mirror baked into the ISO
#   monarch-depends   %DEPENDS% of the monarch package inside the ISO
# Without INSPECT_EXPECT_* nothing is gated (report only). The target image itself is
# not mounted: its package list comes from the build-time pacman -Q record.
set -euo pipefail
ISO=$1 OUT=$2; mkdir -p "$OUT"
sudo apt-get install -y -qq xorriso squashfs-tools >/dev/null
xorriso -osirrox on -indev "$ISO" -extract /arch/x86_64/airootfs.sfs "$OUT/airootfs.sfs" >/dev/null 2>&1
SFS="$OUT/airootfs.sfs"
unsquashfs -d "$OUT/root" -f "$SFS" usr/lib/modules usr/share/monarch-iso usr/share/monarch/install var/lib/pacman/local >/dev/null 2>&1 || true
unsquashfs -l "$SFS" var/cache/monarch/mirror/offline 2>/dev/null | grep -oE '[^/]+\.pkg\.tar\.[a-z0-9]+$' > "$OUT/offline-files.txt" || true
rm -f "$SFS"

strip_ver() { sed -E 's/-[^-]+-[^-]+$//'; }
ls "$OUT/root/usr/lib/modules" > "$OUT/module-dirs.txt" 2>/dev/null || true
ls "$OUT/root/var/lib/pacman/local" 2>/dev/null | strip_ver | sort -u > "$OUT/live-root.txt" || : > "$OUT/live-root.txt"
awk '{print $1}' "$OUT/root/usr/share/monarch-iso/root-image.packages" 2>/dev/null | sort -u > "$OUT/installed-root.txt" || : > "$OUT/installed-root.txt"
cat "$OUT"/root/usr/share/monarch-iso/*.packages "$OUT"/root/usr/share/monarch/install/*.packages 2>/dev/null \
  | grep -v 'root-image' | sed 's/#.*//' | tr -s ' \t' '\n' | sed '/^$/d' | sort -u > "$OUT/installer-lists.txt" || : > "$OUT/installer-lists.txt"
sed -E 's/-[^-]+-[^-]+-[^-]+\.pkg\.tar\.[a-z0-9]+$//' "$OUT/offline-files.txt" | sort -u > "$OUT/offline-mirror.txt"
desc=$(ls -d "$OUT"/root/var/lib/pacman/local/monarch-[0-9]* 2>/dev/null | head -n1 || true)
if [[ -n $desc && -f $desc/desc ]]; then
  sed -n '/^%DEPENDS%/,/^$/p' "$desc/desc" | sed '1d;/^$/d' | sed -E 's/[<>=].*//' | sort -u > "$OUT/monarch-depends.txt"
else : > "$OUT/monarch-depends.txt"; fi

SETS="live-root installed-root installer-lists offline-mirror monarch-depends"
{
echo "kernel module dirs: $(tr '\n' ' ' < "$OUT/module-dirs.txt")"
for s in $SETS; do echo "set $s: $(wc -l < "$OUT/$s.txt") names"; done
echo "(installed-root is the build-time package record of monarch-root.img.zst, not a mounted image)"
for k in linux-cachyos niri noctalia hyprland quickshell waybar walker mako hyprlock uwsm sddm; do
  line="$k:"
  for s in $SETS; do
    m=$(grep -E "^$k(-|\$)" "$OUT/$s.txt" | tr '\n' ',' || true); line="$line  $s=[${m%,}]"
  done
  echo "$line"
done
} | tee "$OUT/report.txt"

rc=0
for p in ${INSPECT_EXPECT_PRESENT:-}; do
  found=0; for s in $SETS; do grep -qx "$p" "$OUT/$s.txt" && found=1; done
  [[ $found == 1 ]] || { echo "GATE FAIL: $p expected present, found in no set"; rc=1; }
done
for p in ${INSPECT_EXPECT_ABSENT:-}; do
  for s in $SETS; do
    m=$(grep -E "^$p(-|\$)" "$OUT/$s.txt" | tr '\n' ' ' || true)
    [[ -z $m ]] || { echo "GATE FAIL: $p family expected absent but found in $s: $m"; rc=1; }
  done
done
[[ -s $OUT/module-dirs.txt ]] || { echo "GATE FAIL: no kernel modules found in live root"; rc=1; }
[[ -s $OUT/installed-root.txt ]] || { echo "WARN: no root-image.packages found, installed-root set is empty"; [[ -z ${INSPECT_EXPECT_ABSENT:-} ]] || rc=1; }
exit $rc
