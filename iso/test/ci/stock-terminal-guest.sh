#!/bin/bash

# STOCK TERMINAL phase. Runs inside the VM guest against the DELIVERED ISO
# state (no fixtures): exercises the supported terminal-provisioning path a
# fresh user would take, then checks the shipped SUPER+Return bind against
# the resulting stock configuration. Independent verdict: does not gate the
# keynav or bar phases.
#
#   1. Evidence for the first-run chicken-and-egg question: with zero
#      terminals installed, the first-steps guide's launcher goes through
#      xdg-terminal-exec - record what it does with nothing to launch.
#   2. monarch-install-terminal foot (the supported stock script): installs
#      the package, writes ~/.config/xdg-terminals.list and the desktop
#      file. Verified, not assumed.
#   3. SUPER+Return (real wtype chord) must then spawn a window, proving
#      the delivered bind works once a terminal is provisioned.
#
# NOTE: the guest had foot pre-installed earlier by the test fixture; this
# phase removes the fixture's user preference file first and treats
# monarch-install-terminal's own results as the stock evidence. Package
# presence from the fixture is acknowledged in the output.
#
# Env: WAYLAND_DISPLAY, HYPRLAND_INSTANCE_SIGNATURE, XDG_RUNTIME_DIR.

set -uo pipefail

OUT=${1:-$HOME/keynav-out}
mkdir -p "$OUT"
LOG=$OUT/stock-terminal.log
exec > >(tee -a "$LOG") 2>&1

fail=0
say() { echo "stock-terminal: $*"; }
bad() { echo "stock-terminal: FAIL: $*"; fail=1; }

say "scope: DELIVERED ISO provisioning path, no fixtures; verdict independent of keynav/bar phases"

# --- 1. xdg-terminal-exec with no configured/installed terminal -------------
rm -f "$HOME/.config/xdg-terminals.list"
say "user xdg-terminals.list removed (fresh-install state apart from packages)"
stock_list=$(cat /etc/xdg/xdg-terminals.list 2>/dev/null || cat /usr/share/monarch/config/xdg-terminals.list 2>/dev/null || echo "(no system xdg-terminals.list found)")
say "system terminal preference list: $stock_list"
say "installed terminal packages: $(pacman -Qq alacritty foot kitty ghostty 2>/dev/null | tr '\n' ' ')(none listed = none)"
echo "--- xdg-terminal-exec with empty user list (first-run launcher state) ---"
timeout 10 xdg-terminal-exec --help >/dev/null 2>&1
xt_out=$(timeout 10 xdg-terminal-exec true 2>&1); xt_rc=$?
say "xdg-terminal-exec exit=$xt_rc output: $xt_out"
[[ $xt_rc -ne 0 ]] && say "as suspected, the GUI installer's terminal launcher fails with no terminal - chicken-and-egg evidence for the first-run flow"

# --- 2. stock provisioning: monarch-install-terminal foot -------------------
echo "--- monarch-install-terminal foot ---"
echo monarch | sudo -S -v
MONARCH_PATH=${MONARCH_PATH:-/usr/share/monarch}
echo monarch | sudo -S "$MONARCH_PATH/bin/monarch-install-terminal" foot 2>&1 | tail -8 || \
  echo monarch | sudo -S monarch-install-terminal foot 2>&1 | tail -8
say "post-install: $(pacman -Qq foot 2>/dev/null || echo 'foot NOT installed')"
say "user xdg-terminals.list: $(cat "$HOME/.config/xdg-terminals.list" 2>/dev/null | grep -v '^#' | head -3 | tr '\n' ' ')"
ls -la "$HOME/.local/share/applications/foot.desktop" /usr/share/applications/foot.desktop 2>&1 | head -3
command -v foot >/dev/null || bad "monarch-install-terminal foot did not yield a foot binary"
grep -q 'foot' "$HOME/.config/xdg-terminals.list" 2>/dev/null || bad "monarch-install-terminal did not write the user preference"

# --- 3. the shipped SUPER+Return bind against the stock config ---------------
clients() { hyprctl clients -j 2>/dev/null | jq '[.[].address] | length'; }
before=$(clients)
timeout 10 wtype -M logo -k Return -m logo
spawned=0
for _ in $(seq 1 30); do
  [[ $(clients) -gt $before ]] && { spawned=1; break; }
  sleep 0.5
done
say "SUPER+Return after stock provisioning: spawned=$spawned (before=$before after=$(clients))"
if [[ $spawned == 1 ]]; then
  say "the shipped Terminal bind works once a terminal is provisioned"
  for a in $(hyprctl clients -j | jq -r '.[].address'); do hyprctl dispatch closewindow "address:$a" >/dev/null 2>&1; done
else
  bad "SUPER+Return spawned no window even after stock provisioning"
fi

if [[ $fail == 0 ]]; then
  say "STOCK-TERMINAL RESULT: GREEN (provisioning path + shipped bind verified)"
  exit 0
fi
say "STOCK-TERMINAL RESULT: RED - see $LOG"
exit 1
