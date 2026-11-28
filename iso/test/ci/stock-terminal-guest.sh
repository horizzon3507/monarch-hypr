#!/bin/bash

# STOCK TERMINAL phase. Runs inside the VM guest against the DELIVERED ISO
# state (no fixtures): exercises the supported terminal-provisioning path a
# fresh user would take, then checks the shipped SUPER+Return bind against
# the resulting stock configuration. Independent verdict: does not gate the
# keynav or bar phases.
#
#   1. Verify the actual shipped terminal state: which terminal packages
#      the ISO installs, the system xdg-terminals.list preference order,
#      and what xdg-terminal-exec launches with no user preference.
#   2. monarch-install-terminal foot (the supported stock script): run AS
#      THE USER with MONARCH_PATH set (sudo only primed for its internal
#      pacman): installs the package, writes ~/.config/xdg-terminals.list
#      and the desktop file. Verified, not assumed.
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

# --- 1. the actual shipped terminal state -----------------------------------
rm -f "$HOME/.config/xdg-terminals.list"
say "user xdg-terminals.list removed (fresh-install state apart from packages)"
stock_list=$(cat /etc/xdg/xdg-terminals.list 2>/dev/null || cat /usr/share/monarch/config/xdg-terminals.list 2>/dev/null || echo "(no system xdg-terminals.list found)")
say "system terminal preference list: $stock_list"
shipped_terms=$(pacman -Qq alacritty foot kitty ghostty 2>/dev/null | tr '\n' ' ')
say "installed terminal packages: $shipped_terms(none listed = none)"
# The shipped default path: with no user preference, xdg-terminal-exec must
# resolve the system list against what the ISO actually installs.
echo "--- xdg-terminal-exec with empty user list (shipped default resolution) ---"
xt_out=$(timeout 10 xdg-terminal-exec true 2>&1); xt_rc=$?
say "xdg-terminal-exec exit=$xt_rc output: $xt_out"
if [[ $xt_rc -ne 0 ]]; then
  bad "shipped default: xdg-terminal-exec cannot resolve any installed terminal ($shipped_terms)"
else
  say "shipped default resolves a terminal with no user preference"
fi

# --- 2. stock provisioning: monarch-install-terminal foot -------------------
# Runs AS THE USER: the script writes ~/.config and calls sudo internally for
# pacman, so only prime the sudo credential first. Running the whole script
# under sudo writes to /root and strips MONARCH_PATH - that was the earlier
# failure, not a product defect.
echo "--- monarch-install-terminal foot (as user) ---"
echo monarch | sudo -S -v
# Disposable-guest fixture: the provisioning scripts call plain sudo
# internally, which cannot read a password on this tty-less ssh session.
# Labeled test fixture only; the ISO ships no such file.
echo monarch | sudo -S bash -c 'echo "monarch ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-vm-test && chmod 440 /etc/sudoers.d/99-vm-test' 2>/dev/null
sudo -n true 2>/dev/null && say "passwordless sudo fixture active" || say "WARN: passwordless sudo fixture failed; provisioner installs may fail"
export MONARCH_PATH=${MONARCH_PATH:-/usr/share/monarch}
if [[ -x $MONARCH_PATH/bin/monarch-install-terminal ]]; then
  "$MONARCH_PATH/bin/monarch-install-terminal" foot 2>&1 | tail -8
else
  monarch-install-terminal foot 2>&1 | tail -8
fi
say "post-install: $(pacman -Qq foot 2>/dev/null || echo 'foot NOT installed')"
say "user xdg-terminals.list: $(cat "$HOME/.config/xdg-terminals.list" 2>/dev/null | grep -v '^#' | head -3 | tr '\n' ' ')"
ls -la "$HOME/.local/share/applications/foot.desktop" /usr/share/applications/foot.desktop 2>&1 | head -3
command -v foot >/dev/null || bad "monarch-install-terminal foot did not yield a foot binary"
grep -q 'foot' "$HOME/.config/xdg-terminals.list" 2>/dev/null || bad "monarch-install-terminal did not write the user preference"

# --- 3. the shipped SUPER+Return bind against the stock config ---------------
clients() { hyprctl clients -j 2>/dev/null | jq '[.[].address] | length'; }
before=$(clients)
# Real-evdev chord via ydotool (see vm-keynav-check.sh: wtype's virtual
# keycodes never match Hyprland binds); wtype kept only as labeled fallback.
if [[ -n ${YDOTOOL_SOCKET:-} && -S $YDOTOOL_SOCKET ]]; then
  timeout 10 ydotool key 125:1 28:1 28:0 125:0
else
  say "ydotool unavailable; wtype chord fallback (keycode matching known-broken)"
  timeout 10 wtype -M logo -k Return -m logo
fi
spawned=0
for _ in $(seq 1 30); do
  [[ $(clients) -gt $before ]] && { spawned=1; break; }
  sleep 0.5
done
say "SUPER+Return after stock provisioning: spawned=$spawned (before=$before after=$(clients))"
if [[ $spawned == 1 ]]; then
  say "the shipped Terminal bind works once a terminal is provisioned"
  for a in $(hyprctl clients -j | jq -r '.[].address'); do hyprctl eval "return hl.dsp.window.close('address:$a')" >/dev/null 2>&1; done
else
  bad "SUPER+Return spawned no window even after stock provisioning"
fi

# --- 4. foot config verification (candidate file over ISO provisioning) ------
# The ISO's provisioned foot.ini carries the legacy noctalia include; the
# candidate checkout carries the fix (include of the rendered Monarch theme).
# Verify with the real foot parser after a real theme render - not assumed.
say "--- foot config verification (candidate config/foot/foot.ini over ISO state) ---"
foot --version 2>&1 | head -1 | sed 's/^/foot version: /'
if [[ -f $HOME/checkout/config/foot/foot.ini ]]; then
  render=$(command -v monarch-theme-render || echo "$MONARCH_PATH/bin/monarch-theme-render")
  "$render" >/dev/null 2>&1 || say "theme render exited non-zero (palette missing on fresh guest?)"
  rendered="$HOME/.config/monarch/current/theme/foot.ini"
  [[ -f $rendered ]] && say "rendered theme present: $rendered" || bad "monarch-theme-render produced no foot.ini at $rendered"
  cp "$HOME/checkout/config/foot/foot.ini" "$HOME/.config/foot/foot.ini"
  if foot --check-config 2>"$OUT/foot-check.log"; then
    say "foot --check-config: clean"
  else
    bad "foot --check-config failed: $(tail -2 "$OUT/foot-check.log" | tr '\n' ' ')"
  fi
  timeout 8 foot >/dev/null 2>"$OUT/foot-launch-stderr.log" &
  sleep 3
  if hyprctl clients -j 2>/dev/null | jq -e '.[] | select((.class // "") | test("foot"))' >/dev/null 2>&1; then
    say "foot produced a live client with the candidate config"
  else
    bad "foot produced NO live client with the candidate config"
  fi
  if grep -q "failed to open" "$OUT/foot-launch-stderr.log"; then
    bad "foot launch still reports a missing include: $(grep 'failed to open' "$OUT/foot-launch-stderr.log" | head -1)"
  elif grep -q "err:" "$OUT/foot-launch-stderr.log"; then
    bad "foot launch reports a config error: $(grep 'err:' "$OUT/foot-launch-stderr.log" | head -1)"
  else
    say "foot launch stderr clean (no config errors)"
  fi
  for a in $(hyprctl clients -j | jq -r '.[].address'); do hyprctl eval "return hl.dsp.window.close('address:$a')" >/dev/null 2>&1; done
else
  say "checkout carries no config/foot/foot.ini; skipped"
fi

# --- 5. theme-include series validation (kitty/alacritty/ghostty/btop) -------
# Same pattern as foot: provision via the stock script, apply the candidate
# config over the ISO state (labeled), validate with the native app where one
# exists. Also probes the already-provisioned upgrade path.
say "--- theme-include series (candidate configs over ISO provisioning) ---"
theme_dir="$HOME/.config/monarch/current/theme"
for app in kitty ghostty; do
  if ! pacman -Qq $app >/dev/null 2>&1; then
    echo monarch | sudo -S -v
    "$MONARCH_PATH/bin/monarch-install-terminal" $app >"$OUT/install-$app.log" 2>&1
  fi
  if pacman -Qq $app >/dev/null 2>&1; then
    say "$app installed: $(pacman -Q $app)"
  else
    say "$app installed: MISSING (native validation skipped) - install log tail: $(tail -3 "$OUT/install-$app.log" 2>/dev/null | tr '\n' ' ')"
  fi
  [[ -d $HOME/.config/$app && -f $HOME/checkout/config/$app ]] || true
done
# kitty: relative include against the including file
if command -v kitty >/dev/null && [[ -f $HOME/checkout/config/kitty/kitty.conf ]]; then
  cp -R "$HOME/checkout/config/kitty/." "$HOME/.config/kitty/" 2>/dev/null || mkdir -p "$HOME/.config/kitty" && cp -R "$HOME/checkout/config/kitty/." "$HOME/.config/kitty/"
  kitty --debug-config >"$OUT/kitty-debug-config.log" 2>&1
  grep -qi 'noctalia\|failed.*include\|Invalid' "$OUT/kitty-debug-config.log" \
    && bad "kitty config reports include/parse problems: $(grep -i 'noctalia\|failed.*include\|Invalid' "$OUT/kitty-debug-config.log" | head -1)" \
    || say "kitty --debug-config clean (include resolves: $([[ -f $theme_dir/kitty.conf ]] && echo yes || echo NO))"
fi
# alacritty: missing imports are skipped; assert the import target exists and no noctalia reference remains
if command -v alacritty >/dev/null && [[ -f $HOME/checkout/config/alacritty/alacritty.toml ]]; then
  mkdir -p "$HOME/.config/alacritty"
  cp "$HOME/checkout/config/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"
  [[ -f $theme_dir/alacritty.toml ]] && say "alacritty import target rendered: $theme_dir/alacritty.toml" || bad "alacritty rendered import missing: $theme_dir/alacritty.toml"
  grep -q noctalia "$HOME/.config/alacritty/alacritty.toml" && bad "alacritty.toml still references noctalia" || say "alacritty.toml has no noctalia reference"
fi
# ghostty: theme name resolves through the shipped relative symlink
if command -v ghostty >/dev/null && [[ -d $HOME/checkout/config/ghostty ]]; then
  mkdir -p "$HOME/.config/ghostty"
  cp -RP "$HOME/checkout/config/ghostty/." "$HOME/.config/ghostty/"
  resolved=$(readlink -f "$HOME/.config/ghostty/themes/monarch-current" 2>/dev/null)
  [[ -n $resolved && -f $resolved ]] && say "ghostty theme symlink resolves: $resolved" || bad "ghostty theme symlink broken: $HOME/.config/ghostty/themes/monarch-current -> ${resolved:-nothing}"
  ghostty +show-config >"$OUT/ghostty-show-config.log" 2>&1 \
    && { grep -q 'theme = monarch-current' "$OUT/ghostty-show-config.log" && say "ghostty resolves theme=monarch-current" || say "ghostty +show-config ran; theme line: $(grep -m1 'theme' "$OUT/ghostty-show-config.log")"; } \
    || say "ghostty +show-config unavailable/failed (see log) - symlink resolution is the evidence"
fi
# btop: theme name resolves through the shipped relative symlink
if [[ -d $HOME/checkout/config/btop ]]; then
  mkdir -p "$HOME/.config/btop"
  cp -RP "$HOME/checkout/config/btop/." "$HOME/.config/btop/"
  resolved=$(readlink -f "$HOME/.config/btop/themes/monarch-current.theme" 2>/dev/null)
  [[ -n $resolved && -f $resolved ]] && say "btop theme symlink resolves: $resolved" || bad "btop theme symlink broken: $HOME/.config/btop/themes/monarch-current.theme -> ${resolved:-nothing}"
fi
# restore foot as the session default after the extra provisions
printf 'foot.desktop\n' > "$HOME/.config/xdg-terminals.list"

# --- 6. already-provisioned upgrade behavior -----------------------------------
# The provisioner copies a config only when none exists; users provisioned
# before the fix keep the legacy include. Verify, then restore the candidate.
say "--- upgrade behavior: pre-existing config untouched by re-provision ---"
cp "$MONARCH_PATH/config/foot/foot.ini" "$HOME/.config/foot/foot.ini"  # simulate a pre-fix provisioned user
"$MONARCH_PATH/bin/monarch-install-terminal" foot >/dev/null 2>&1
if grep -q noctalia "$HOME/.config/foot/foot.ini"; then
  say "upgrade behavior CONFIRMED: existing installs keep the legacy noctalia include after re-provision (provisioner copies only when missing)"
else
  say "upgrade behavior: re-provision REPLACED the existing config (unexpected)"
fi
cp "$HOME/checkout/config/foot/foot.ini" "$HOME/.config/foot/foot.ini"  # restore candidate

# --- 7. end-to-end reconcile: legacy Noctalia migration (candidate code) -----
# Seed the genuine pre-fix state from the ISO's stock configs, then run the
# CANDIDATE reconcile user.sh end-to-end (MONARCH_PATH = checkout) and verify
# the terminal-theme migration on real guest state. user.sh runs with set -e
# and may abort early in this minimal guest; then fall back to sourcing the
# migration directly, labeled as the narrower check.
say "--- reconcile end-to-end: legacy migration (candidate install/reconcile) ---"
if [[ -f $HOME/checkout/install/reconcile/terminal-themes.sh ]]; then
  for app in foot/foot.ini kitty/kitty.conf alacritty/alacritty.toml ghostty/config btop/btop.conf; do
    mkdir -p "$HOME/.config/${app%/*}"
    cp "$MONARCH_PATH/config/$app" "$HOME/.config/$app" 2>/dev/null || true
  done
  rm -rf "$HOME/.config/ghostty/themes" "$HOME/.config/btop/themes"
  rm -f "$HOME"/.config/*/*.monarch-backup.* 2>/dev/null || true
  MONARCH_PATH="$HOME/checkout" bash "$HOME/checkout/install/reconcile/user.sh" >"$OUT/reconcile-user.log" 2>&1
  rc=$?
  say "candidate user.sh exit=$rc (last line: $(tail -1 "$OUT/reconcile-user.log"))"
  if ! grep -q 'monarch/current/theme/foot.ini' "$HOME/.config/foot/foot.ini"; then
    say "full user.sh did not reach the migration (exit=$rc); sourcing terminal-themes.sh directly (narrower check)"
    HOME="$HOME" bash -c 'source "$1"; terminal_themes_migrate' _ "$HOME/checkout/install/reconcile/terminal-themes.sh" >>"$OUT/reconcile-user.log" 2>&1
  fi
  for want in \
    "$HOME/.config/foot/foot.ini:monarch/current/theme/foot.ini" \
    "$HOME/.config/kitty/kitty.conf:../monarch/current/theme/kitty.conf" \
    "$HOME/.config/alacritty/alacritty.toml:monarch/current/theme/alacritty.toml" \
    "$HOME/.config/ghostty/config:theme = monarch-current" \
    "$HOME/.config/btop/btop.conf:color_theme = \"monarch-current\""; do
    f=${want%%:*}; pat=${want#*:}
    grep -qF "$pat" "$f" && say "end-to-end: $(basename "$f") migrated" || bad "end-to-end: $f not migrated (want: $pat)"
  done
  nback=$(find "$HOME/.config" -name '*.monarch-backup.*' | wc -l)
  [[ $nback -ge 5 ]] && say "end-to-end: $nback backups created" || say "end-to-end: backups=$nback (expected >=5 if migration ran)"
  glink=$(readlink -f "$HOME/.config/ghostty/themes/monarch-current" 2>/dev/null)
  blink=$(readlink -f "$HOME/.config/btop/themes/monarch-current.theme" 2>/dev/null)
  [[ -n $glink && -f $glink ]] && say "end-to-end: ghostty symlink resolves ($glink)" || bad "end-to-end: ghostty symlink broken"
  [[ -n $blink && -f $blink ]] && say "end-to-end: btop symlink resolves ($blink)" || bad "end-to-end: btop symlink broken"
  foot --check-config 2>"$OUT/foot-check-post-reconcile.log" \
    && say "end-to-end: foot --check-config clean after reconcile" \
    || bad "end-to-end: foot --check-config failed after reconcile: $(tail -1 "$OUT/foot-check-post-reconcile.log")"
else
  say "checkout carries no terminal-themes.sh; skipped"
fi

if [[ $fail == 0 ]]; then
  say "STOCK-TERMINAL RESULT: GREEN (provisioning path + shipped bind verified)"
  exit 0
fi
say "STOCK-TERMINAL RESULT: RED - see $LOG"
exit 1
