#!/bin/bash
# Static inspection of a built ISO. Prints findings; fails loudly on extraction
# problems and on the gates the commit under test declares, so an intermediate
# ISO is not held to final claims.
#
#   inspect-iso.sh <iso> <outdir>        extract from the ISO, then analyze
#   inspect-iso.sh --analyze <outdir>    analyze an already extracted tree (used by tests)
#
# Gates (environment):
#   INSPECT_EXPECT_PRESENT       exact names that must be in installed-root (the target image record)
#   INSPECT_EXPECT_PRESENT_LIVE  exact names that must be in live-root
#   INSPECT_EXPECT_ABSENT        package FAMILIES (name or name-*) that must appear in NO set
#   INSPECT_EXPECT_ABSENT_INSTALLED  package FAMILIES that must be absent from the installed image side
#                                (installed-root, installer-lists, offline-mirror, monarch-depends) but may
#                                stay in the live session (live-root)
# Declaring any gate also requires every set below to be non-empty, so an
# extraction or parsing failure cannot pass as "nothing found".
#
# Sets (<outdir>/<set>.txt, one package name per line):
#   live-root        pacman local db of the live system (airootfs.sfs)
#   installed-root   build-time `pacman -Q` record of monarch-root.img.zst (root-image.packages)
#   installer-lists  usr/share/monarch-iso/*.packages and usr/share/monarch/install/*.packages,
#                    excluding root-image.packages
#   offline-mirror   package files in the offline mirror baked into the ISO
#   monarch-depends  %DEPENDS% of the monarch package, read without mounting the target image:
#                    first from the offline mirror database (offline.db.tar.gz in the squashfs),
#                    then from the live root pacman db. If neither has the package the set is
#                    UNAVAILABLE (never reported as empty/pass).
# UNAVAILABLE monarch-depends fails any gated run, unless INSPECT_ALLOW_UNAVAILABLE=1 (an explicit,
# printed waiver for intermediate builds; a final gate must not set it).
# Dependency strings and installer lists are reported but never satisfy PRESENT.
# The target image itself is not mounted: installed-root is the build-time record.
set -uo pipefail

extract() {
  local iso=$1 out=$2 sfs_in_iso sfs
  mkdir -p "$out"; rm -f "$out/extract.status"
  sudo apt-get install -y -qq xorriso squashfs-tools >/dev/null || { echo "GATE FAIL: cannot install xorriso/squashfs-tools"; return 1; }
  sfs_in_iso=/arch/x86_64/airootfs.sfs
  if ! xorriso -indev "$iso" -find "$sfs_in_iso" -type f 2>/dev/null | grep -qx "'$sfs_in_iso'"; then
    sfs_in_iso=$(xorriso -indev "$iso" -find / -name '*.sfs' -type f 2>/dev/null | head -n1 | tr -d "'")
  fi
  [[ -n $sfs_in_iso ]] || { echo "GATE FAIL: no squashfs found in the ISO"; return 1; }
  echo "squashfs in ISO: $sfs_in_iso" | tee "$out/squashfs-path.txt"
  sfs="$out/airootfs.sfs"
  xorriso -osirrox on -indev "$iso" -extract "$sfs_in_iso" "$sfs" >/dev/null 2>&1 && [[ -s $sfs ]] \
    || { echo "GATE FAIL: could not extract $sfs_in_iso"; return 1; }
  unsquashfs -d "$out/root" -f "$sfs" usr/lib/modules usr/share/monarch-iso var/lib/pacman/local >/dev/null 2>&1 \
    || { echo "GATE FAIL: unsquashfs of required paths failed"; return 1; }
  unsquashfs -d "$out/root" -f "$sfs" usr/share/monarch/install >/dev/null 2>&1 || true   # optional
  unsquashfs -d "$out/root" -f "$sfs" var/cache/monarch/mirror/offline/offline.db.tar.gz >/dev/null 2>&1 || true   # optional
  unsquashfs -l "$sfs" var/cache/monarch/mirror/offline 2>/dev/null | grep -oE '[^/]+\.pkg\.tar\.[a-z0-9]+$' > "$out/offline-files.txt"
  rm -f "$sfs"
  echo ok > "$out/extract.status"
}

analyze() {
  local out=$1 s p m found k line rc=0 gated=0
  [[ -n ${INSPECT_EXPECT_PRESENT:-}${INSPECT_EXPECT_PRESENT_LIVE:-}${INSPECT_EXPECT_ABSENT:-}${INSPECT_EXPECT_ABSENT_INSTALLED:-} ]] && gated=1
  [[ $(cat "$out/extract.status" 2>/dev/null) == ok ]] || { echo "GATE FAIL: extraction did not complete (no extract.status=ok)"; return 1; }
  local root=$out/root sets="live-root installed-root installer-lists offline-mirror monarch-depends"
  strip_ver() { sed -E 's/-[^-]+-[^-]+$//'; }

  ls "$root/usr/lib/modules" > "$out/module-dirs.txt" 2>/dev/null
  ls "$root/var/lib/pacman/local" 2>/dev/null | strip_ver | sort -u > "$out/live-root.txt"
  awk '{print $1}' "$root/usr/share/monarch-iso/root-image.packages" 2>/dev/null | sort -u > "$out/installed-root.txt"
  : > "$out/installer-lists.txt.tmp"
  for f in "$root"/usr/share/monarch-iso/*.packages "$root"/usr/share/monarch/install/*.packages; do
    [[ -f $f && $(basename "$f") != root-image.packages ]] || continue
    sed 's/#.*//' "$f" | tr -s ' \t' '\n' | sed '/^$/d' >> "$out/installer-lists.txt.tmp"
  done
  sort -u "$out/installer-lists.txt.tmp" > "$out/installer-lists.txt"; rm -f "$out/installer-lists.txt.tmp"
  sed -E 's/-[^-]+-[^-]+-[^-]+\.pkg\.tar\.[a-z0-9]+$//' "$out/offline-files.txt" 2>/dev/null | sort -u > "$out/offline-mirror.txt"
  # monarch %DEPENDS%: offline mirror db first, then the live root db. Neither => UNAVAILABLE.
  local depsrc="" depdesc=""
  : > "$out/monarch-depends.txt"
  local db="$root/var/cache/monarch/mirror/offline/offline.db.tar.gz"
  if [[ -f $db ]]; then
    depdesc=$(tar -tzf "$db" 2>/dev/null | grep -E '^monarch-[0-9][^/]*/desc$' | head -n1)
    if [[ -n $depdesc ]]; then
      tar -xzOf "$db" "$depdesc" 2>/dev/null | sed -n '/^%DEPENDS%/,/^$/p' | sed '1d;/^$/d' | sed -E 's/[<>=].*//' | sort -u > "$out/monarch-depends.txt"
      depsrc="offline mirror db ($depdesc)"
    fi
  fi
  if [[ -z $depsrc ]]; then
    local desc; desc=$(ls -d "$root"/var/lib/pacman/local/monarch-[0-9]* 2>/dev/null | head -n1)
    if [[ -n $desc && -f $desc/desc ]]; then
      sed -n '/^%DEPENDS%/,/^$/p' "$desc/desc" | sed '1d;/^$/d' | sed -E 's/[<>=].*//' | sort -u > "$out/monarch-depends.txt"
      depsrc="live root pacman db ($desc)"
    fi
  fi
  [[ -n $depsrc ]] && echo "$depsrc" > "$out/monarch-depends.source" || echo UNAVAILABLE > "$out/monarch-depends.source"

  {
    echo "kernel module dirs: $(tr '\n' ' ' < "$out/module-dirs.txt")"
    for s in $sets; do echo "set $s: $(wc -l < "$out/$s.txt") names"; done
    echo "(installed-root is the build-time package record of monarch-root.img.zst, not a mounted image)"
    echo "monarch-depends source: $(cat "$out/monarch-depends.source")"
    for k in linux-cachyos niri noctalia hyprland quickshell waybar walker mako hyprlock uwsm sddm; do
      line="$k:"
      for s in $sets; do m=$(grep -E "^$k(-|\$)" "$out/$s.txt" | tr '\n' ','); line="$line  $s=[${m%,}]"; done
      echo "$line"
    done
  } | tee "$out/report.txt"

  [[ -s $out/module-dirs.txt ]] || { echo "GATE FAIL: no kernel modules found in live root"; rc=1; }
  if [[ $gated == 1 ]]; then
    for s in $sets; do
      [[ -s $out/$s.txt ]] && continue
      if [[ $s == monarch-depends && $(cat "$out/monarch-depends.source") == UNAVAILABLE ]]; then
        if [[ ${INSPECT_ALLOW_UNAVAILABLE:-} == 1 ]]; then
          echo "NOTE: monarch-depends UNAVAILABLE (monarch package found in neither the offline mirror db nor the live root); waived by INSPECT_ALLOW_UNAVAILABLE=1, its dependencies are NOT verified"
        else
          echo "GATE FAIL: monarch-depends UNAVAILABLE (monarch package found in neither the offline mirror db nor the live root); not a pass"; rc=1
        fi
        continue
      fi
      echo "GATE FAIL: set $s is empty (extraction or parsing problem)"; rc=1
    done
  fi
  for p in ${INSPECT_EXPECT_PRESENT:-}; do
    grep -qx "$p" "$out/installed-root.txt" || { echo "GATE FAIL: $p expected in installed-root (target image record)"; rc=1; }
  done
  for p in ${INSPECT_EXPECT_PRESENT_LIVE:-}; do
    grep -qx "$p" "$out/live-root.txt" || { echo "GATE FAIL: $p expected in live-root"; rc=1; }
  done
  for p in ${INSPECT_EXPECT_ABSENT:-}; do
    for s in $sets; do
      m=$(grep -E "^$p(-|\$)" "$out/$s.txt" | tr '\n' ' ')
      [[ -z $m ]] || { echo "GATE FAIL: $p family expected absent but found in $s: $m"; rc=1; }
    done
  done
  for p in ${INSPECT_EXPECT_ABSENT_INSTALLED:-}; do
    for s in installed-root installer-lists offline-mirror monarch-depends; do
      m=$(grep -E "^$p(-|\$)" "$out/$s.txt" | tr '\n' ' ')
      [[ -z $m ]] || { echo "GATE FAIL: $p family expected absent from the installed image but found in $s: $m"; rc=1; }
    done
  done
  return $rc
}

if [[ ${1:-} == --analyze ]]; then
  analyze "${2:?outdir}"; exit $?
fi
ISO=${1:?iso} OUT=${2:?outdir}
extract "$ISO" "$OUT" || exit 1
analyze "$OUT"
