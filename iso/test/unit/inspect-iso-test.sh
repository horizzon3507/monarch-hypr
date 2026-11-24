#!/bin/bash
# Fixture tests for test/ci/inspect-iso.sh --analyze (no ISO, no root needed).
set -uo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
script=$root/test/ci/inspect-iso.sh
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fails=0

# mkfix <name> : a good fixture. live has linux-cachyos+hyprland, target image has hyprland, no niri/noctalia
mkfix() {
  local d=$tmp/$1; rm -rf "$d"; mkdir -p "$d/root/usr/lib/modules/6.12.1-cachyos" "$d/root/usr/share/monarch-iso" \
    "$d/root/usr/share/monarch/install" "$d/root/var/lib/pacman/local/linux-cachyos-6.12.1-1" \
    "$d/root/var/lib/pacman/local/hyprland-0.45.0-1" "$d/root/var/lib/pacman/local/monarch-0.1.0-1"
  printf '%%DEPENDS%%\nhyprland\nbash>=5\n\n' > "$d/root/var/lib/pacman/local/monarch-0.1.0-1/desc"
  printf 'linux-cachyos 6.12.1-1\nhyprland 0.45.0-1\nmonarch 0.1.0-1\n' > "$d/root/usr/share/monarch-iso/root-image.packages"
  printf 'hyprland\n# comment\nquickshell\n' > "$d/root/usr/share/monarch-iso/monarch-base.packages"
  printf 'firefox\n' > "$d/root/usr/share/monarch/install/monarch-other.packages"
  printf 'hyprland-0.45.0-1-x86_64.pkg.tar.zst\nlinux-cachyos-6.12.1-1-x86_64.pkg.tar.zst\n' > "$d/offline-files.txt"
  echo ok > "$d/extract.status"
  echo "$d"
}
# run <name> <expected rc: 0|1> <env...> -- fixture dir
check() {
  local name=$1 want=$2 d=$3; shift 3
  env "$@" bash "$script" --analyze "$d" > "$tmp/out.txt" 2>&1; local rc=$?
  [[ $rc == "$want" || ( $want == 1 && $rc != 0 ) ]] && echo "ok   $name" || { echo "FAIL $name (rc=$rc want=$want)"; sed 's/^/     /' "$tmp/out.txt"; fails=$((fails+1)); }
}
has() { grep -qx "$2" "$1" && echo ok || echo no; }

d=$(mkfix success);   check "success with all gates" 0 "$d" INSPECT_EXPECT_PRESENT="hyprland linux-cachyos" INSPECT_EXPECT_PRESENT_LIVE=hyprland INSPECT_EXPECT_ABSENT="niri noctalia"
d=$(mkfix report);    check "report-only mode passes without gates" 0 "$d" X=1
d=$(mkfix noextract); rm "$d/extract.status"; check "missing extract.status fails" 1 "$d" INSPECT_EXPECT_ABSENT=niri
d=$(mkfix badstatus); echo failed > "$d/extract.status"; check "extract.status not ok fails" 1 "$d" X=1
d=$(mkfix emptyroot); rm "$d/root/usr/share/monarch-iso/root-image.packages"; check "missing target record fails when absence gated" 1 "$d" INSPECT_EXPECT_ABSENT=niri
d=$(mkfix emptymirror); : > "$d/offline-files.txt"; check "empty offline mirror fails when gated" 1 "$d" INSPECT_EXPECT_ABSENT=niri
d=$(mkfix emptylive); rm -rf "$d"/root/var/lib/pacman/local/*; check "empty live db fails when gated" 1 "$d" INSPECT_EXPECT_ABSENT=niri
d=$(mkfix nodepends); rm -rf "$d"/root/var/lib/pacman/local/monarch-*; check "missing monarch package fails when gated" 1 "$d" INSPECT_EXPECT_ABSENT=niri
d=$(mkfix nomodules); rm -rf "$d/root/usr/lib/modules/6.12.1-cachyos"; check "no kernel modules fails" 1 "$d" X=1
d=$(mkfix wishlist);  sed -i '/^hyprland/d' "$d/root/usr/share/monarch-iso/root-image.packages"; check "PRESENT not satisfied by wishlist or depends" 1 "$d" INSPECT_EXPECT_PRESENT=hyprland
d=$(mkfix livepresent); rm -rf "$d/root/var/lib/pacman/local/hyprland-0.45.0-1"; check "PRESENT_LIVE needs live-root" 1 "$d" INSPECT_EXPECT_PRESENT_LIVE=hyprland
d=$(mkfix fam1); mkdir "$d/root/var/lib/pacman/local/niri-git-25.1-1"; check "absent family niri-git in live-root" 1 "$d" INSPECT_EXPECT_ABSENT=niri
d=$(mkfix fam2); echo 'noctalia-qs-0.2-3-x86_64.pkg.tar.zst' >> "$d/offline-files.txt"; check "absent family noctalia-qs in offline mirror" 1 "$d" INSPECT_EXPECT_ABSENT=noctalia
d=$(mkfix fam3); echo 'noctalia-shell' >> "$d/root/usr/share/monarch-iso/monarch-other.packages"; check "absent family in installer list" 1 "$d" INSPECT_EXPECT_ABSENT=noctalia
d=$(mkfix fam4); sed -i 's/^bash.*//;s/^hyprland$/hyprland\nniri/' "$d/root/var/lib/pacman/local/monarch-0.1.0-1/desc"; check "absent family in monarch depends" 1 "$d" INSPECT_EXPECT_ABSENT=niri
d=$(mkfix fam5); echo 'niri-sessions 1.0-1' >> "$d/root/usr/share/monarch-iso/root-image.packages"; check "absent family in target record" 1 "$d" INSPECT_EXPECT_ABSENT=niri
d=$(mkfix nonfam); mkdir "$d/root/var/lib/pacman/local/nirikit-1.0-1"; check "name sharing only a prefix is not the family" 0 "$d" INSPECT_EXPECT_ABSENT=niri
# file exclusion: names only in root-image.packages must not leak into installer-lists
d=$(mkfix excl); echo 'secretpkg 9.9-1' >> "$d/root/usr/share/monarch-iso/root-image.packages"
env X=1 bash "$script" --analyze "$d" >/dev/null 2>&1
[[ $(has "$d/installer-lists.txt" secretpkg) == no && $(has "$d/installed-root.txt" secretpkg) == ok && $(has "$d/installer-lists.txt" 9.9-1) == no ]] \
  && echo "ok   root-image.packages excluded from installer-lists" || { echo "FAIL exclusion"; fails=$((fails+1)); }
[[ $(has "$d/installer-lists.txt" quickshell) == ok && $(has "$d/installer-lists.txt" firefox) == ok && $(has "$d/installer-lists.txt" '#') == no ]] \
  && echo "ok   installer lists read from both directories, comments dropped" || { echo "FAIL installer lists"; fails=$((fails+1)); }
# version stripping of local db and offline filenames
[[ $(has "$d/live-root.txt" linux-cachyos) == ok && $(has "$d/offline-mirror.txt" hyprland) == ok && $(has "$d/monarch-depends.txt" bash) == ok ]] \
  && echo "ok   version suffixes stripped" || { echo "FAIL stripping"; fails=$((fails+1)); }

[[ $fails == 0 ]] && echo "all inspect-iso tests passed" || { echo "$fails failed"; exit 1; }
