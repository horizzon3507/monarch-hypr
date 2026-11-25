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
# Log in at the SDDM greeter with the keyboard, the way a person would. The
# test account password is the harness default; this is a disposable VM.
capture_console "success-greeter-before-login"
type_text "$GUEST_PASSWORD"; sleep 1; press ret
for i in 1 2 3 4 5 6; do
  sleep 15
  capture_console "success-after-login-$((i * 15))s"
done
g "retired families: installed packages matching niri or noctalia (must be empty)" ssh_guest 'q=$(pacman -Qq) && [ -n "$q" ] && { echo "installed packages: $(wc -l <<<"$q")"; grep -E "^(niri|noctalia)(-|$)" <<<"$q" || echo "none matched"; }'
g "NetworkManager" ssh_guest 'systemctl is-active NetworkManager; nmcli -t general status 2>&1 | head -3; nmcli -t -f DEVICE,TYPE,STATE device 2>&1 | head -5'
g "sessions after login" ssh_guest 'loginctl list-sessions --no-legend'
g "processes after login" ssh_guest 'pgrep -a "Hyprland|quickshell|hyprpaper|mako|swayosd|hypridle|sddm-greeter" || echo none'
g "hyprctl after login" ssh_guest 'u=$(id -u); export XDG_RUNTIME_DIR=/run/user/$u; sig=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1); echo "sig=$sig"; HYPRLAND_INSTANCE_SIGNATURE=$sig hyprctl version 2>&1 | head -4; HYPRLAND_INSTANCE_SIGNATURE=$sig hyprctl layers 2>&1 | head -30'
g "user units" ssh_guest 'systemctl --user list-units --no-legend --state=failed; systemctl --user list-units --no-legend "app-uwsm*" "wayland-wm*" | head'
g "wallpaper state before restart" ssh_guest 'pgrep -a hyprpaper || echo "hyprpaper not running"; find ~/.config/monarch ~/.local/state/monarch -maxdepth 3 \( -name "background*" -o -name "*wallpaper*" \) -exec ls -l {} + 2>&1 | head'
g "wallpaper link (current/background) and hyprpaper log" ssh_guest 'ls -l ~/.config/monarch/current/background; ls -lL ~/.config/monarch/current/background 2>&1; readlink -f ~/.config/monarch/current/background 2>&1; journalctl --user -b --no-pager 2>/dev/null | grep -i hyprpaper | grep -iE "ERR|target|path" | tail -5'
capture_console "success-wallpaper-before-restart"
g "wallpaper state json equals resolved link, before restart" ssh_guest 'c=$HOME/.config/monarch/current; r=$(readlink -f "$c/background"); j=$(jq -r .path "$c/wallpaper.json" 2>&1); rev=$(jq -r .rev "$c/wallpaper.json" 2>&1); echo "link -> $r"; echo "wallpaper.json path=$j rev=$rev"; if [ -f "$r" ] && [ "$j" = "$r" ]; then echo "WALLPAPER-STATE PASS"; else echo "WALLPAPER-STATE FAIL"; fi; ls -l "$c/background" "$c/wallpaper.json" 2>&1'
g "monarch restart shell" ssh_guest 'u=$(id -u); export XDG_RUNTIME_DIR=/run/user/$u; export HYPRLAND_INSTANCE_SIGNATURE=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1); timeout 60 monarch restart shell 2>&1 | tail -20'
sleep 10
g "after restart" ssh_guest 'pgrep -a "hyprpaper|quickshell|mako|swayosd|hypridle" || echo none'
capture_console "success-after-shell-restart"
g "wallpaper link after restart (selection must be preserved)" ssh_guest 'readlink -f ~/.config/monarch/current/background 2>&1'
g "wallpaper state json equals resolved link, after restart" ssh_guest 'c=$HOME/.config/monarch/current; r=$(readlink -f "$c/background"); j=$(jq -r .path "$c/wallpaper.json" 2>&1); rev=$(jq -r .rev "$c/wallpaper.json" 2>&1); echo "link -> $r"; echo "wallpaper.json path=$j rev=$rev"; if [ -f "$r" ] && [ "$j" = "$r" ]; then echo "WALLPAPER-STATE PASS"; else echo "WALLPAPER-STATE FAIL"; fi; ls -l "$c/background" "$c/wallpaper.json" 2>&1'
# Obsidian user service outside the desktop environment, with a disposable test vault (not the real app).
g "obsidian theme user service (disposable vault, systemd user manager)" ssh_guest 'export XDG_RUNTIME_DIR=/run/user/$(id -u); echo "path unit: enabled=$(systemctl --user is-enabled monarch-obsidian-theme.path 2>&1) active=$(systemctl --user is-active monarch-obsidian-theme.path 2>&1)"; v=$HOME/test-vault; mkdir -p "$v/.obsidian" $HOME/.config/obsidian; printf "{\"vaults\":{\"t\":{\"path\":\"%s\"}}}\n" "$v" > $HOME/.config/obsidian/obsidian.json; sleep 6; echo "service after path trigger: result=$(systemctl --user show monarch-obsidian-theme.service -p Result -p ExecMainStatus -p ActiveState --value | tr "\n" " ")"; ls -l "$v/.obsidian/snippets/monarch.css" 2>&1; cat "$v/.obsidian/appearance.json" 2>&1; systemctl --user start monarch-obsidian-theme.service; echo "manual start exit=$?"; jq -c .enabledCssSnippets "$v/.obsidian/appearance.json" 2>&1; echo "rendered css bytes: $(stat -c %s $(readlink -f "$v/.obsidian/snippets/monarch.css") 2>&1)"; journalctl --user -u monarch-obsidian-theme.service --no-pager 2>&1 | tail -6; if [ -L "$v/.obsidian/snippets/monarch.css" ] && jq -e ".enabledCssSnippets|index(\"monarch\")!=null" "$v/.obsidian/appearance.json" >/dev/null 2>&1; then echo "OBSIDIAN-SERVICE PASS"; else echo "OBSIDIAN-SERVICE FAIL"; fi'
# Night light (hyprsunset), only when the installed system has the package.
if ssh_guest 'pacman -Q hyprsunset' >/dev/null 2>&1; then
  g "hyprsunset package" ssh_guest 'pacman -Q hyprsunset; hyprsunset --version 2>&1 | head -2'
  NL='u=$(id -u); export XDG_RUNTIME_DIR=/run/user/$u; export WAYLAND_DISPLAY=$(cd "$XDG_RUNTIME_DIR" && ls wayland-* 2>/dev/null | grep -v lock | head -1); export HYPRLAND_INSTANCE_SIGNATURE=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)'
  g "hyprsunset foreground probe (5s, env check)" ssh_guest "$NL; echo WAYLAND_DISPLAY=\$WAYLAND_DISPLAY; timeout 5 hyprsunset -t 4000 2>&1 | head -8; echo rc=\$?"
  g "nightlight toggle (monarch) on" ssh_guest "$NL; timeout 40 monarch toggle nightlight 2>&1 | tail -5; echo \"toggle exit=\${PIPESTATUS[0]}\"; sleep 3; pgrep -a hyprsunset || echo 'hyprsunset not running'; r=\$(monarch toggle nightlight status 2>&1); echo \"monarch status after on: \$r exit=\$?\""
  g "nightlight raw hyprctl identity after on (raw false means filter ON, true means OFF)" ssh_guest "$NL; timeout 20 hyprctl hyprsunset identity get 2>&1 | head -3; systemctl --user status --no-pager 2>&1 | grep -i hyprsunset | head -3"
  capture_console "success-nightlight-on"
  g "nightlight toggle off" ssh_guest "$NL; timeout 40 monarch toggle nightlight 2>&1 | tail -5; echo \"toggle exit=\${PIPESTATUS[0]}\"; sleep 2; echo raw identity after off:; timeout 20 hyprctl hyprsunset identity get 2>&1 | head -3; r=\$(monarch toggle nightlight status 2>&1); echo \"monarch status after off: \$r\""
  capture_console "success-nightlight-off"
  g "nightlight raw IPC (4000, identity true, get)" ssh_guest "$NL; hyprctl hyprsunset temperature 4000 2>&1; hyprctl hyprsunset identity get 2>&1; hyprctl hyprsunset identity true 2>&1; hyprctl hyprsunset identity get 2>&1"
else
  note "nightlight: hyprsunset not installed on this ISO, check skipped"
fi
# ---- Bounded extras, run after the core proof so they cannot mask it. Test VM
# credentials only. Anything ambiguous is labelled INCONCLUSIVE, not pass/fail.
ENVSET='u=$(id -u); export XDG_RUNTIME_DIR=/run/user/$u; export WAYLAND_DISPLAY=$(cd "$XDG_RUNTIME_DIR" && ls wayland-* 2>/dev/null | grep -v lock | head -1); export HYPRLAND_INSTANCE_SIGNATURE=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)'
echo "--- EXTRA escape: open a panel, press Escape" >>"$R"
ssh_guest "$ENVSET; timeout 20 monarch-panel open theme" >>"$R" 2>&1
sleep 3; capture_console "success-extra-panel-open"
press esc; sleep 3; capture_console "success-extra-panel-after-escape"
n=$(ssh_guest "$ENVSET; hyprctl layers 2>/dev/null | grep -c 'namespace: quickshell'")
echo "quickshell layers after Escape: $n (bar only = 1; more means the panel layer is still present). RESULT: judge from the screenshots success-extra-panel-open / -after-escape; script does not auto-decide." >>"$R"
ssh_guest "$ENVSET; timeout 20 monarch-panel close theme" >>"$R" 2>&1

echo "--- EXTRA lock/unlock with the test account password" >>"$R"
capture_console "success-extra-lock-before"
ssh_guest "$ENVSET; setsid -f monarch-system-lock >/tmp/lock.out 2>&1; sleep 4; pgrep -a hyprlock || echo 'hyprlock not running'; cat /tmp/lock.out" >>"$R" 2>&1
sleep 3; capture_console "success-extra-lock-screen"
type_text "$GUEST_PASSWORD"; sleep 1; press ret; sleep 6
capture_console "success-extra-lock-after-unlock"
ssh_guest "pgrep -a hyprlock || echo 'hyprlock gone after unlock attempt'" >>"$R" 2>&1
echo "lock/unlock: RESULT from the three success-extra-lock-* screenshots plus the hyprlock process lines above; if the password prompt was not shown or keys did not reach it, treat as INCONCLUSIVE." >>"$R"

# ---- Real apps with the rendered Monarch theme (online job only: needs the package repos).
# Bounded. Anything that does not reach a usable app window is INCONCLUSIVE, not a pass.
if [[ ${MONARCH_INTEGRATION_OFFLINE:-} == false ]]; then
  echo "--- APPS rendered theme files as resolved in the guest" >>"$R"
  ssh_guest 'for f in obsidian.css helix.toml; do echo "== $f ($(stat -c %s ~/.config/monarch/current/theme/$f) bytes)"; cat ~/.config/monarch/current/theme/$f; done; grep -c "{{" ~/.config/monarch/current/theme/obsidian.css ~/.config/monarch/current/theme/helix.toml' >>"$R" 2>&1
  echo "--- APPS install helix and obsidian from the repos (online test VM)" >>"$R"
  ssh_sudo 'echo "ISO-installed before: $(pacman -Q qt6-base qt6-declarative quickshell hyprland 2>&1 | tr "\n" " ")"; timeout 300 pacman -Sy --noconfirm 2>&1 | tail -2; echo "after db refresh, upgradable packages (partial-upgrade state if we install only helix+obsidian): $(pacman -Qu 2>/dev/null | wc -l)"; pacman -Qu 2>/dev/null | grep -E "qt6|quickshell|hyprland|electron|mesa" | head -8; timeout 900 pacman -S --noconfirm --needed helix obsidian 2>&1 | tail -6; echo "pacman exit=${PIPESTATUS[0]}"; echo "installed after: $(pacman -Q helix obsidian electron qt6-base quickshell 2>&1 | tr "\n" " ")"' >>"$R" 2>&1
  ssh_guest "$ENVSET; timeout 120 monarch-install-helix 2>&1 | tail -4; echo install-helix exit=\$?; ls -l ~/.config/helix/themes/ ~/.config/helix/config.toml; cat ~/.config/helix/config.toml" >>"$R" 2>&1
  echo "--- APPS helix in alacritty with the monarch theme" >>"$R"
  ssh_guest "$ENVSET; printf 'fn main() {\n    let s = \"hello\"; // note\n    let n: u32 = 42;\n}\n' > ~/t.rs; setsid -f alacritty -e helix ~/t.rs >/tmp/hx.out 2>&1; sleep 10; pgrep -a helix || echo 'helix not running'; hx --health 2>&1 | head -0; cat /tmp/hx.out | head -5" >>"$R" 2>&1
  capture_console "success-app-helix"
  ssh_guest "pkill -x helix; pkill -x alacritty; true" >/dev/null 2>&1
  echo "--- DIAG apply the source fix: pin the Wayland platform in user-flags.conf (as config/obsidian/user-flags.conf now does)" >>"$R"
  ssh_guest "printf -- '--ozone-platform=wayland\n' >> ~/.config/obsidian/user-flags.conf; cat ~/.config/obsidian/user-flags.conf" >>"$R" 2>&1
  echo "--- DIAG obsidian package, wrapper and electron runtime" >>"$R"
  ssh_guest 'pacman -Qi obsidian | grep -E "^(Version|Depends On)"; pacman -Q | grep -i electron; echo "wrapper:"; head -20 /usr/bin/obsidian; ls -d ~/.config/obsidian ~/.config/obsidian/user-flags.conf 2>&1' >>"$R" 2>&1
  echo "--- DIAG obsidian foreground run, exit code and stderr (40 s bound)" >>"$R"
  ssh_guest "$ENVSET; v=\$HOME/test-vault; printf '{\"vaults\":{\"tv\":{\"path\":\"%s\",\"ts\":1,\"open\":true}}}\n' \"\$v\" > ~/.config/obsidian/obsidian.json; timeout 40 obsidian --enable-logging=stderr --v=0 >/tmp/ob-diag.out 2>&1; echo obsidian-exit=\$?; wc -l /tmp/ob-diag.out; tail -40 /tmp/ob-diag.out | cut -c1-300" >>"$R" 2>&1
  echo "--- DIAG same run with --no-sandbox --disable-gpu --ozone-platform=wayland" >>"$R"
  ssh_guest "$ENVSET; timeout 40 obsidian --no-sandbox --disable-gpu --ozone-platform=wayland --enable-logging=stderr >/tmp/ob-diag2.out 2>&1; echo obsidian-exit=\$?; tail -25 /tmp/ob-diag2.out | cut -c1-300" >>"$R" 2>&1
  echo "--- DIAG crash evidence" >>"$R"
  ssh_sudo 'coredumpctl list --no-pager 2>&1 | tail -5; journalctl -b --no-pager | grep -i -E "obsidian|electron|coredump|segfault" | grep -v "Obsidian vaults" | tail -15 | cut -c1-300; dmesg 2>/dev/null | grep -i -E "obsidian|electron|segfault|oom" | tail -5' >>"$R" 2>&1
  echo "--- APPS obsidian opening the disposable test vault (Electron, software renderer)" >>"$R"
  ssh_guest "$ENVSET; v=\$HOME/test-vault; printf '{\"vaults\":{\"tv\":{\"path\":\"%s\",\"ts\":1,\"open\":true}}}\n' \"\$v\" > ~/.config/obsidian/obsidian.json; sleep 3; jq -c .enabledCssSnippets \$v/.obsidian/appearance.json; setsid -f obsidian >/tmp/ob.out 2>&1; sleep 30; pgrep -a obsidian | head -2 | cut -c1-120 || true; tail -5 /tmp/ob.out; hyprctl clients 2>/dev/null | grep -iE 'class|title' | head -4" >>"$R" 2>&1
  capture_console "success-app-obsidian"
  ssh_guest "$ENVSET; if ! pgrep -x obsidian >/dev/null; then echo 'obsidian not running, retry with --no-sandbox --disable-gpu'; setsid -f obsidian --no-sandbox --disable-gpu >/tmp/ob2.out 2>&1; sleep 30; tail -5 /tmp/ob2.out; fi; pgrep -c obsidian" >>"$R" 2>&1
  capture_console "success-app-obsidian-2"
  for f in success-app-helix success-app-obsidian success-app-obsidian-2; do
    [[ -f $OUT/$f.png ]] && echo "$f center pixel $(magick "$OUT/$f.png" -format '%[pixel:p{640,400}] corner %[pixel:p{20,780}]' info: 2>&1)" >>"$R"
  done
  echo "apps: screenshots success-app-*.png must be read; a window that shows the vault or helix buffer with the Monarch term_bg (printed above in obsidian.css) is evidence, a blank/crashed window is INCONCLUSIVE. Not a claim for the user's real hardware." >>"$R"
fi
ssh_sudo 'journalctl -b --no-pager' >"$OUT/journal-cold-boot.log" 2>/dev/null
g "journal: sddm/uwsm/hyprland/quickshell (last 60)" bash -c "grep -iE 'sddm|uwsm|hyprland|quickshell' '$OUT/journal-cold-boot.log' | tail -60"
note "RESULT: install, reboot and cold boot reached SSH. Read report.txt and the screenshots for the session outcome; no desktop claim is made by this script."
collect
exit 0
