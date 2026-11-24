#!/bin/bash

# Unattended install + reboot check on a GitHub-hosted runner. Reuses the QEMU
# helpers in test/integration.d/base-test.sh (owned by the integration side):
# builds a cidata autoinstall drive, installs the ISO onto a blank disk, lets
# the installer reboot into the installed system, then cold-boots the installed
# disk a second time and records what the session manager did.
#
# It records evidence and fails only when the install or the boots fail. What a
# screenshot or a journal line proves is for the reader to judge.
#
# Usage: bash test/ci/install-reboot-check.sh ISO OUT_DIR
# Env:   MONARCH_INTEGRATION_OFFLINE=true runs the install with no Internet.
#
# Disposable runner only: it opens /dev/kvm to every user.

set -uo pipefail

ISO=$(realpath "$1") OUT=$2
HERE=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)
mkdir -p "$OUT"
OUT=$(realpath "$OUT")

sudo apt-get update -qq
sudo apt-get install -y -qq qemu-system-x86 qemu-utils ovmf imagemagick tesseract-ocr socat xorriso openssh-client jq >/dev/null

# base-test.sh was written for an Arch host: OVMF path and `magick` binary.
sudo mkdir -p /usr/share/edk2/x64
for f in CODE VARS; do
  src=/usr/share/OVMF/OVMF_${f}_4M.fd
  [[ -f $src ]] || src=/usr/share/OVMF/OVMF_${f}.fd
  sudo ln -sf "$src" "/usr/share/edk2/x64/OVMF_${f}.4m.fd"
done
command -v magick >/dev/null || sudo ln -sf "$(command -v convert)" /usr/local/bin/magick

ACCEL=tcg
if [[ -e /dev/kvm ]]; then
  echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules >/dev/null
  sudo udevadm control --reload-rules; sudo udevadm trigger --name-match=kvm
  [[ -w /dev/kvm ]] || sudo chmod 666 /dev/kvm
  [[ -w /dev/kvm ]] && ACCEL=kvm
fi

# The disk image does not fit next to the ISO on the small root volume.
if [[ -d /mnt ]]; then
  sudo mkdir -p /mnt/monarch-runs && sudo chown "$USER" /mnt/monarch-runs
  rm -rf "$HERE/../../test-runs"; ln -s /mnt/monarch-runs "$HERE/../../test-runs"
fi

export MONARCH_INTEGRATION_ISO=$ISO MONARCH_INTEGRATION_NO_PREVIEW=true
export MONARCH_INTEGRATION_ACCEL=$ACCEL MONARCH_INTEGRATION_CPUS=$(nproc)
export MONARCH_INTEGRATION_MEMORY=${MONARCH_INTEGRATION_MEMORY:-6144}
export MONARCH_INTEGRATION_INSTALL_TIMEOUT=${MONARCH_INTEGRATION_INSTALL_TIMEOUT:-3000}
SCENARIO=install-reboot
# shellcheck source=../integration.d/base-test.sh
source "$HERE/../integration.d/base-test.sh"
set +e

R="$OUT/report.txt"
note() { echo "$*" | tee -a "$R"; }
note "accel=$ACCEL offline=${MONARCH_INTEGRATION_OFFLINE:-false} iso=$(basename "$ISO") mem=$MEMORY cpus=$CPUS"
collect() { # copy evidence out of the run dir, keep going on errors
  cp -a "$RUN_DIR"/*.png "$RUN_DIR"/*.log "$OUT"/ 2>/dev/null
  cp -a "$BASE_DIR"/monarch-install*.{json,log} "$BASE_DIR"/first-boot-systemd-analyze.txt "$OUT"/ 2>/dev/null
}
trap 'collect' EXIT

t0=$SECONDS
install_phase
rc=$?
note "install_phase rc=$rc wall=$((SECONDS - t0))s (install plus first reboot into the installed disk)"
collect
if ((rc != 0)) || ! base_image_ready; then
  note "RESULT: install did not complete"; exit 1
fi

# Second, cold boot of the installed disk (throwaway overlay).
t1=$SECONDS
start_vm_from_base
if ! wait_for_ssh "$BOOT_TIMEOUT" failure-cold-boot-ssh; then
  note "RESULT: installed disk cold boot: SSH never came up"; collect; exit 1
fi
note "cold boot to SSH: $((SECONDS - t1))s"
capture_console "success-cold-boot-ssh"

for i in 1 2 3 4 5 6; do
  sleep 30
  capture_console "success-after-boot-$((i * 30))s"
done

g() { echo "--- $1" >>"$R"; shift; "$@" >>"$R" 2>&1; }
g "pacman -Q" ssh_guest 'pacman -Q monarch linux-cachyos hyprland quickshell uwsm sddm niri noctalia 2>&1'
g "root fs" ssh_guest 'findmnt -n -o FSTYPE,SOURCE /'
g "sddm active" ssh_guest 'systemctl is-active sddm'
g "failed units" ssh_guest 'systemctl --failed --no-legend'
g "sessions" ssh_guest 'loginctl list-sessions --no-legend; ls /usr/share/wayland-sessions'
g "processes" ssh_guest 'pgrep -a "Hyprland|quickshell|sddm|uwsm|hyprpaper|mako|swayosd" || echo none'
g "sddm config" ssh_sudo 'cat /etc/sddm.conf.d/* 2>/dev/null | head -40'
g "hyprctl" ssh_guest 'u=$(id -u); XDG_RUNTIME_DIR=/run/user/$u hyprctl -i "$(ls /run/user/$u/hypr 2>/dev/null | head -1)" version 2>&1 | head -5'
g "wallpaper state before restart" ssh_guest 'pgrep -a hyprpaper || echo "hyprpaper not running"; find ~/.config/monarch ~/.local/state/monarch -maxdepth 3 \( -name "background*" -o -name "*wallpaper*" \) -exec ls -l {} + 2>&1 | head'
capture_console "success-before-shell-restart"
g "monarch restart shell" ssh_guest 'u=$(id -u); export XDG_RUNTIME_DIR=/run/user/$u; export HYPRLAND_INSTANCE_SIGNATURE=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1); timeout 60 monarch restart shell 2>&1 | tail -20'
sleep 10
g "after restart" ssh_guest 'pgrep -a "hyprpaper|quickshell|mako|swayosd|hypridle" || echo none'
capture_console "success-after-shell-restart"
ssh_sudo 'journalctl -b --no-pager' >"$OUT/journal-cold-boot.log" 2>/dev/null
g "journal: sddm/uwsm/hyprland/quickshell (last 60)" bash -c "grep -iE 'sddm|uwsm|hyprland|quickshell' '$OUT/journal-cold-boot.log' | tail -60"
note "RESULT: install, reboot and cold boot reached SSH. Read report.txt and the screenshots for the session outcome; no desktop claim is made by this script."
collect
exit 0
