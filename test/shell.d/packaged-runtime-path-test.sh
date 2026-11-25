#!/bin/bash

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

runtime="$test_tmp/runtime"
home="$test_tmp/home"
mkdir -p "$runtime/bin" "$home" "$test_tmp/bin"
cp "$ROOT/bin/monarch-toggle-chat-privacy" "$runtime/bin/"
cp "$ROOT/bin/monarch-toggle" "$runtime/bin/"

grep -qF 'MONARCH_PATH=${MONARCH_PATH:-/usr/share/monarch}' "$ROOT/config/uwsm/env" ||
  fail "the graphical session does not default to the packaged runtime"
grep -qF 'MONARCH_RUNTIME_ROOT:-/usr/share/monarch' "$ROOT/default/shells/envs" ||
  fail "shell sessions do not prefer the packaged runtime"
grep -qF 'MONARCH_PATH=$HOME/.local/share/monarch' "$ROOT/default/shells/envs" ||
  fail "shell sessions cannot recover through the legacy checkout"
for rc in "$ROOT/default/zsh/rc" "$ROOT/default/bash/rc"; do
  grep -qF '${MONARCH_RUNTIME_ROOT:-/usr/share/monarch}/bin/monarch' "$rc" ||
    fail "$(basename "$(dirname "$rc")") does not check the packaged runtime"
  grep -qF 'MONARCH_PATH=$HOME/.local/share/monarch' "$rc" ||
    fail "$(basename "$(dirname "$rc")") cannot recover through the legacy checkout"
done
pass "login sessions prefer the packaged runtime and retain upgrade recovery"

hypr_runtime="$test_tmp/hypr-runtime"
hypr_home="$test_tmp/hypr-home"
mkdir -p "$hypr_runtime/default" "$hypr_runtime/config" "$hypr_runtime/install/user" "$hypr_home"
cp -R "$ROOT/default/hypr" "$hypr_runtime/default/hypr"
cp -R "$ROOT/config/hypr" "$hypr_runtime/config/hypr"
cp "$ROOT/install/user/detect-keyboard-layout.sh" "$hypr_runtime/install/user/"

cat >"$test_tmp/bin/Hyprland" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$HOME/hyprland-calls"
[[ ! -e $HOME/validation-fails ]]
EOF
chmod +x "$test_tmp/bin/Hyprland"

if ! HOME="$hypr_home" MONARCH_PATH="$hypr_runtime" PATH="$test_tmp/bin:$PATH" \
  bash "$ROOT/bin/monarch-refresh-hypr"; then
  fail "refresh hypr runs against the packaged runtime fixture"
fi
hypr_target="$hypr_home/.config/hypr/hyprland.lua"
grep -qF "local root = \"$hypr_runtime\"" "$hypr_target" ||
  fail "refresh hypr expands the selected runtime path"
if grep -qF '@MONARCH_PATH@' "$hypr_target"; then
  fail "refresh hypr leaves an unexpanded runtime placeholder"
fi
for user_file in monitors input bindings looknfeel autostart keyboard; do
  [[ -f $hypr_home/.config/hypr/$user_file.lua ]] ||
    fail "refresh hypr seeds $user_file.lua so the config loads"
done
grep -qF -- "--verify-config" "$hypr_home/hyprland-calls" ||
  fail "refresh hypr validates the assembled config"

printf '%s\n' '-- DP-1 disabled' >"$hypr_home/.config/hypr/monitors.lua"
HOME="$hypr_home" MONARCH_PATH="$hypr_runtime" PATH="$test_tmp/bin:$PATH" \
  bash "$ROOT/bin/monarch-refresh-hypr" || fail "refresh hypr is idempotent"
grep -qF 'DP-1 disabled' "$hypr_home/.config/hypr/monitors.lua" ||
  fail "refresh hypr preserves user edits"
if compgen -G "$hypr_home/.config/hypr/hyprland.lua.bak.*" >/dev/null; then
  fail "refresh hypr backs up an unchanged entry point"
fi

touch "$hypr_home/validation-fails"
if HOME="$hypr_home" MONARCH_PATH="$hypr_runtime" PATH="$test_tmp/bin:$PATH" \
  bash "$ROOT/bin/monarch-refresh-hypr" 2>/dev/null; then
  fail "refresh hypr succeeds after a failed validation"
fi
pass "refresh hypr installs, preserves user files and fails on invalid config"

if grep -R -q '%h/.local/share/monarch/bin/' "$ROOT/config/systemd/user"; then
  fail "a user service still invokes a checkout-only command path"
fi
pass "user services invoke packaged Monarch commands"

for command in monarch-theme-apply monarch-theme-bundle monarch-theme-list; do
  grep -qF '$HOME/.config/monarch/themes' "$ROOT/bin/$command" ||
    fail "$command does not keep user themes under ~/.config/monarch"
done
grep -qF '$HOME/.config/monarch/themes' "$ROOT/default/monarch/monarch-menu.jsonc" ||
  fail "the menu does not discover user themes under ~/.config/monarch"
for retired_command in monarch-reinstall-git monarch-sudo-reset; do
  [[ ! -e $ROOT/bin/$retired_command ]] ||
    fail "the package runtime still exposes $retired_command"
done
if "$ROOT/bin/monarch" commands --all --json |
  jq -e '.commands[] | select(.binary == "monarch-sudo-reset" or .route == "monarch sudo reset")' >/dev/null; then
  fail "the command router still exposes the retired sudo reset command"
fi
pass "retired checkout and sudo reset commands are absent from the package runtime"

runtime_commands=(
  monarch-install-tailscale
  monarch-plymouth-preview
  monarch-refresh-sddm
  monarch-theme-background-import
  monarch-theme-background-list
  monarch-theme-background-remove
  monarch-theme-list
  monarch-unlock-list
)
for command in "${runtime_commands[@]}"; do
  if grep -Eq '\$HOME/\.local/share/monarch/(bin|config|default|install|themes)' "$ROOT/bin/$command"; then
    fail "$command still defaults to a checkout-only runtime"
  fi
done
pass "theme and Tailscale commands default to the packaged Monarch runtime"
