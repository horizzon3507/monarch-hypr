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
# 1920x1080 so the bar-layout phase can switch the guest output up to 1920.
Xvfb :99 -screen 0 1920x1080x24 &
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
# TEST FIXTURE: foot + xdg-terminal-exec exist here only to give the keynav
# smoke's SUPER+Return bind witness something to spawn. The ISO deliberately
# ships NO terminal (monarch-install-terminal is the post-install flow), so
# this says nothing about the delivered ISO; on a real install the user's
# chosen terminal answers the bind. foot is shm-based (no GL, unlike the
# shipped default preference Alacritty, which never spawned on llvmpipe).
# adwaita-icon-theme: the tray fixture's IconName (dialog-information) must
# resolve to a real icon; without a theme the shell shows its missing-icon
# fallback squares, which read as a rendering bug in the bar screenshots.
echo monarch | sudo -S pacman -Sy --needed --noconfirm git wtype wev grim qt6-wayland jq foot xdg-terminal-exec adwaita-icon-theme ydotool 2>&1 | tail -3
# uinput daemon for ydotool: modifier chords are injected as real evdev
# keycodes (KEY_LEFTMETA=125) because wtype's virtual-keyboard keycodes never
# match Hyprland's keycode-based binds (q arrived as keycode 9 in VM runs).
export YDOTOOL_SOCKET=/tmp/.ydotool_socket
pgrep -x ydotoold >/dev/null 2>&1 || echo monarch | sudo -S -b env YDOTOOL_SOCKET=$YDOTOOL_SOCKET ydotoold >/dev/null 2>&1
sleep 1
echo monarch | sudo -S chmod 0666 "$YDOTOOL_SOCKET" 2>/dev/null || true
[[ -S $YDOTOOL_SOCKET ]] && echo "ydotoold up on $YDOTOOL_SOCKET" || echo "WARNING: ydotoold socket missing; chords fall back to wtype"
mkdir -p "$HOME/.config"
printf 'foot.desktop\n' > "$HOME/.config/xdg-terminals.list"
# Disposable guest home hygiene: an empty .zshrc suppresses the
# zsh-newuser-install wizard in fixture terminals. This is guest setup,
# NOT evidence about the shipped first-run user experience.
touch "$HOME/.zshrc"
rm -rf "$HOME/checkout"
git clone --quiet https://github.com/horizzon3507/monarch-hypr.git "$HOME/checkout"
cd "$HOME/checkout"
git fetch --quiet --depth 1 origin "$sha" || git fetch --quiet origin feat/panel-keynav
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
echo "--- session evidence ---"
timeout 10 hyprctl configerrors 2>&1 | tail -6
hyprctl binds -j > "$HOME/keynav-out/hyprctl-binds.json" 2>/dev/null || true
hyprctl version -j 2>/dev/null | head -c 400; echo
echo "--- end session evidence ---"
# Foot spawn probe: last run's SUPER+Return witness never produced a window
# and the bar phase's `dispatch exec foot` produced none either (all 10
# workspaces listed 0 windows). Isolate whether foot can spawn at all here.
echo "--- foot spawn probe ---"
foot --version 2>&1 | head -2
ldd "$(command -v foot)" 2>/dev/null | grep 'not found' || echo "foot libs: all resolved"
timeout 8 foot >"$HOME/keynav-out/foot-stdout.log" 2>"$HOME/keynav-out/foot-stderr.log" &
sleep 3
echo "clients after manual foot: $(hyprctl clients -j | jq -c '[.[] | {class}]')"
echo "foot stderr:"; tail -5 "$HOME/keynav-out/foot-stderr.log"
hyprctl dispatch exec foot >/dev/null 2>&1
sleep 3
echo "clients after dispatch exec foot: $(hyprctl clients -j | jq -c '[.[] | {class}]')"
for a in $(hyprctl clients -j | jq -r '.[].address'); do hyprctl dispatch closewindow "address:$a" >/dev/null 2>&1; done
sleep 1
echo "--- end foot spawn probe ---"
SMOKE_ATTACH=1 SMOKE_COMPOSITOR=hyprland \
  bash test/quickshell-keynav-smoke.sh --screenshots "$HOME/keynav-out" 2>&1 | tee "$HOME/keynav-out/smoke-full.log" | tail -80
echo "keynav exit: ${PIPESTATUS[0]}"
echo "--- bar layout phase ---"
if [[ -f iso/test/ci/bar-layout-guest.sh ]]; then
  bash iso/test/ci/bar-layout-guest.sh "$HOME/keynav-out" 2>&1 | tail -60
  echo "bar-layout exit: ${PIPESTATUS[0]}"
else
  echo "bar-layout phase not present in this checkout; skipped"
fi
echo "--- stock terminal phase ---"
if [[ -f iso/test/ci/stock-terminal-guest.sh ]]; then
  bash iso/test/ci/stock-terminal-guest.sh "$HOME/keynav-out" 2>&1 | tail -30
  echo "stock-terminal exit: ${PIPESTATUS[0]}"
fi
echo "--- base shell interception comparison ---"
# Inherited-baseline check: does the PRE-PR122 shell also let compositor
# binds fire while its session panel is open? Same VM, same compositor, same
# input path - only the shell code differs (99e0f22, pre-PR122). This keeps
# base-ISO evidence separate from candidate-code verdicts. The panel-open
# state is VERIFIED via layer-shell namespaces before the chord; an
# unverified panel makes the comparison invalid (last round's failure).
panel_open() { # any layer-shell namespace mentioning 'session'
  hyprctl layers -j 2>/dev/null | jq -r '.. | .namespace? // empty' | grep -qi session
}
BASE=99e0f22a7704a3f609361a9c6b5a6e1fb9ebd931
if git -C "$HOME/checkout" fetch --quiet --depth 1 origin "$BASE" \
  && git -C "$HOME/checkout" worktree add --detach "$HOME/base-shell" "$BASE" >/dev/null 2>&1; then
  pkill -x quickshell 2>/dev/null; sleep 2
  quickshell -p "$HOME/base-shell/default/quickshell" >"$HOME/keynav-out/base-qs.log" 2>&1 &
  sleep 8
  kill -0 $! 2>/dev/null || { echo "base shell died; see base-qs.log"; tail -10 "$HOME/keynav-out/base-qs.log"; }
  pkill -x foot 2>/dev/null; pkill -x wev 2>/dev/null; sleep 1   # clean client baseline
  bw=$(hyprctl monitors -j | jq -r '.[0].width')
  # ydotool absolute coordinates are scaled vs output pixels on this stack
  # (observed x2 at 640x480): calibrate first.
  ydotool mousemove --absolute -x 100 -y 100 2>/dev/null; sleep 0.4
  cpos=$(hyprctl cursorpos 2>/dev/null | tr -d ' ')
  csx=$(( ${cpos%%,*} / 100 )); csy=$(( ${cpos##*,} / 100 ))
  [[ $csx -lt 1 ]] && csx=1; [[ $csy -lt 1 ]] && csy=1
  echo "base-phase pointer scale: ${csx}x${csy} (from 100,100 -> $cpos)"
  # click-delivery control: workspace indicator 3 must switch the workspace
  bws0=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // 0')
  ydotool mousemove --absolute -x $((106 / csx)) -y $((14 / csy)) 2>/dev/null; sleep 0.4
  ydotool click 0xC0 2>/dev/null; sleep 0.8
  bws1=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // 0')
  echo "base-phase click-delivery control: workspace $bws0 -> $bws1 after indicator click"
  ydotool mousemove --absolute -x $((26 / csx)) -y $((14 / csy)) 2>/dev/null; sleep 0.4
  ydotool click 0xC0 2>/dev/null; sleep 0.8   # back to workspace 1
  # open the base session panel via the power glyph; verify, retry up to 3x
  panel=0
  for try in 1 2 3; do
    ydotool mousemove --absolute -x $(( (bw - 16) / csx )) -y $(( 15 / csy )) 2>/dev/null; sleep 0.4
    echo "power-click cursorpos (try $try): $(hyprctl cursorpos 2>/dev/null | tr -d ' ') (target $((bw-16)),15)"
    ydotool click 0xC0 2>/dev/null
    for i in $(seq 1 20); do panel_open && break; sleep 0.2; done
    panel_open && { panel=1; break; }
    echo "base panel not verified open after try $try; retrying"
  done
  grim "$HOME/keynav-out/base-panel-open.png" 2>/dev/null || true
  if [[ $panel == 1 ]]; then
    bpre=$(hyprctl clients -j | jq length)
    ydotool key 125:1 28:1 28:0 125:0 2>/dev/null; sleep 4
    bpost=$(hyprctl clients -j | jq length)
    grim "$HOME/keynav-out/base-after-chord.png" 2>/dev/null || true
    echo "base shell ($BASE) VERIFIED-open panel SUPER+Return: clients $bpre -> $bpost"
    [[ $bpost -gt $bpre ]] && echo "base shell: bind fired through VERIFIED-open panel (INHERITED BASELINE)" \
      || echo "base shell: bind did NOT fire through VERIFIED-open panel (candidate behavior would be a regression)"
  else
    echo "base shell comparison INVALID: base session panel never verified open after 3 clicks"
  fi
  pkill -x quickshell 2>/dev/null
else
  echo "base shell comparison skipped: could not fetch/check out $BASE"
fi
GUEST
keynav_rc=${PIPESTATUS[0]}
collect

note "vm-keynav-check done (guest stream rc=$keynav_rc)"
# The guest stream's own "keynav exit:" line is the smoke verdict; surface it.
gate_rc=0
if grep -q 'keynav exit: 0' "$R"; then
  note "RESULT: keynav smoke GREEN on real Hyprland (candidate $CANDIDATE_SHA)"
else
  note "RESULT: keynav smoke NOT green or indeterminate - see report"
  # The gate must not bless a failed verdict: fail the workflow. The
  # artifact upload step has if: always(), so diagnostics still upload.
  gate_rc=1
fi
# Bar layout phase (present on branches carrying the bar fix): same rule.
if grep -q 'bar-layout exit:' "$R"; then
  if grep -q 'bar-layout exit: 0' "$R"; then
    note "RESULT: bar layout GREEN on real Hyprland (candidate $CANDIDATE_SHA)"
  else
    note "RESULT: bar layout RED or indeterminate - see report"
    gate_rc=1
  fi
fi
# Stock terminal provisioning: reported separately, does not gate.
if grep -q 'stock-terminal exit:' "$R"; then
  if grep -q 'stock-terminal exit: 0' "$R"; then
    note "RESULT: stock terminal provisioning GREEN (delivered-ISO path)"
  else
    note "RESULT: stock terminal provisioning RED (informational, not gating) - see stock-terminal.log"
  fi
fi
exit $gate_rc
