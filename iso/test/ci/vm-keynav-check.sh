#!/bin/bash

# On-target keyboard-navigation validation in a disposable VM. Installs the
# given Monarch ISO unattended (cidata), boots the installed disk with
# GPU-less virgl graphics (Xvfb + llvmpipe on the host, real DRM render node
# in the guest), enables SDDM autologin so the real Hyprland session comes
# up, then clones the fork at the exact candidate SHA inside the guest and
# runs the keynav smoke in attach mode: the OS/compositor/session come from
# the ISO, but the shell under test is the candidate code.
#
# Proof labels stay separate: the report records both the ISO's source SHA
# (environment) and the tested candidate SHA (code under test).
#
# Usage: bash test/ci/vm-keynav-check.sh ISO CANDIDATE_SHA OUT_DIR
# Disposable runner only: it opens /dev/kvm to every user.

set -uo pipefail

[[ -f ${1:-} ]] || { echo "error: ISO not found: '${1:-}'" >&2; exit 2; }
ISO=$(realpath "$1") CANDIDATE_SHA=$2 OUT=$3
HERE=$(cd -- "${BASH_SOURCE%/*}" && pwd)
mkdir -p "$OUT"
OUT=$(realpath "$OUT")

sudo apt-get update -qq
sudo apt-get install -y -qq qemu-system-x86 qemu-system-gui qemu-utils ovmf libvirglrenderer1 libegl1 libgl1 xvfb imagemagick tesseract-ocr socat xorriso openssh-client jq >/dev/null

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

# Host GL for virgl: llvmpipe over Xvfb.
Xvfb :99 -screen 0 1024x768x24 &
XVFB_PID=$!
sleep 2
export DISPLAY=:99
trap 'kill $XVFB_PID 2>/dev/null || true' EXIT

export MONARCH_INTEGRATION_ISO=$ISO MONARCH_INTEGRATION_NO_PREVIEW=true
export MONARCH_INTEGRATION_ACCEL=$ACCEL MONARCH_INTEGRATION_CPUS=$(nproc)
export MONARCH_INTEGRATION_MEMORY=${MONARCH_INTEGRATION_MEMORY:-8192}
export MONARCH_INTEGRATION_INSTALL_TIMEOUT=${MONARCH_INTEGRATION_INSTALL_TIMEOUT:-3600}
export MONARCH_INTEGRATION_GL=gtk-xvfb
SCENARIO=vm-keynav
# shellcheck source=../integration.d/base-test.sh
source "$HERE/../integration.d/base-test.sh"
set +e

R="$OUT/report.txt"
note() { echo "$*" | tee -a "$R"; }
note "accel=$ACCEL iso=$(basename "$ISO") candidate=$CANDIDATE_SHA"
note "PROOF SCOPE: ISO provides OS/compositor/session environment only; the shell under test is the candidate checkout."

collect() {
  ssh_guest 'tar czf - -C /home/monarch keynav-out 2>/dev/null' >"$OUT/keynav-out.tar.gz" 2>/dev/null
  cp -a "$RUN_DIR"/*.png "$RUN_DIR"/*.log "$OUT"/ 2>/dev/null
}

t0=$SECONDS
install_phase
rc=$?
note "install_phase rc=$rc wall=$((SECONDS - t0))s"
if ((rc != 0)) || ! base_image_ready; then
  note "RESULT: install did not complete"; collect; exit 1
fi

# Boot the installed disk (throwaway overlay) with virgl graphics.
start_vm_from_base
if ! wait_for_ssh "$BOOT_TIMEOUT" failure-boot-ssh; then
  note "RESULT: installed system did not reach SSH"; collect; exit 1
fi

# Enable autologin into the monarch session and reboot so the real Hyprland
# session starts on the virgl GPU.
ssh_sudo 'mkdir -p /etc/sddm.conf.d && printf "[Autologin]\nUser=monarch\nSession=monarch.desktop\n" > /etc/sddm.conf.d/zz-vm-keynav.conf'
ssh_sudo 'systemctl reboot' || true
sleep 20
if ! wait_for_ssh "$BOOT_TIMEOUT" failure-reboot-ssh; then
  note "RESULT: system did not come back after autologin reboot"; collect; exit 1
fi

# Wait for the graphical session's wayland socket.
for _ in $(seq 1 60); do
  ssh_guest 'ls /run/user/1000/wayland-* 2>/dev/null | head -1' | grep -q wayland && break
  sleep 5
done
ssh_guest 'ls -l /run/user/1000/wayland-* 2>/dev/null; ls -l /dev/dri 2>/dev/null; loginctl list-sessions 2>/dev/null' | tee -a "$R"

# Everything below runs in the guest; stream its output into the report.
ssh_guest 'bash -s' -- "$CANDIDATE_SHA" <<'GUEST' | tee -a "$R"
set -x
sha=$1
export PATH="$PATH"
sudo -n true 2>/dev/null || echo monarch | sudo -S true
echo monarch | sudo -S pacman -Sy --needed --noconfirm git wtype wev grim qt6-wayland 2>&1 | tail -3
rm -rf "$HOME/checkout"
git clone --quiet https://github.com/horizzon3507/monarch-hypr.git "$HOME/checkout"
cd "$HOME/checkout"
git fetch --quiet --depth 50 origin feat/panel-keynav || true
git checkout --quiet "$sha" || { echo "CANDIDATE CHECKOUT FAILED for $sha"; exit 1; }
echo "tested candidate SHA: $(git rev-parse HEAD)"
echo "guest render nodes:"; ls -l /dev/dri
mkdir -p "$HOME/keynav-out"
# Attach to the running Hyprland session; the smoke restarts the shell from
# this checkout with stub PATH and drives real wtype keys.
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY=$(basename "$(ls $XDG_RUNTIME_DIR/wayland-* | grep -v lock | head -1)")
export HYPRLAND_INSTANCE_SIGNATURE=$(ls "$XDG_RUNTIME_DIR/hypr" | head -1)
echo "wayland=$WAYLAND_DISPLAY his=$HYPRLAND_INSTANCE_SIGNATURE"
SMOKE_ATTACH=1 SMOKE_COMPOSITOR=hyprland \
  bash test/quickshell-keynav-smoke.sh --screenshots "$HOME/keynav-out" 2>&1 | tail -60
echo "keynav exit: ${PIPESTATUS[0]}"
GUEST
keynav_rc=${PIPESTATUS[0]}
collect

note "vm-keynav-check done (guest stream rc=$keynav_rc)"
# The guest stream's own "keynav exit:" line is the smoke verdict; surface it.
if grep -q 'keynav exit: 0' "$R"; then
  note "RESULT: keynav smoke GREEN on real Hyprland (candidate $CANDIDATE_SHA)"
else
  note "RESULT: keynav smoke NOT green or indeterminate - see report"
fi
