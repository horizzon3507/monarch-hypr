#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export HOME="$test_tmp/home"
export MONARCH_PATH="$ROOT"
mkdir -p "$test_tmp/bin" "$HOME"
cat >"$test_tmp/bin/hyprctl" <<'STUB'
#!/bin/bash
echo "hyprctl $*" >>"$TEST_LOG"
[[ ${HYPRCTL_FAIL:-} != 1 ]]
STUB
chmod +x "$test_tmp/bin/hyprctl"
export TEST_LOG="$test_tmp/log" PATH="$test_tmp/bin:$PATH"

toggle="$ROOT/bin/monarch-toggle-chat-privacy"
flag="$HOME/.local/state/monarch/toggles/chat-privacy-off"
: >"$TEST_LOG"

# Rules: the Hyprland rules file hides chat windows and rules.lua honours the flag.
grep -q 'no_screen_share = true' "$ROOT/default/hypr/chat-privacy.lua" || fail "Hyprland rules mask chat windows"
grep -q 'chat-privacy-off' "$ROOT/default/hypr/rules.lua" || fail "rules.lua reads the toggle flag"

"$toggle" status | jq -e '.enabled == true' >/dev/null
pass "fresh installations have chat masking on"

# Inside a Hyprland session every change reloads it.
export HYPRLAND_INSTANCE_SIGNATURE=test
"$toggle" off
[[ -f $flag ]] || fail "off sets the flag"
"$toggle" status | jq -e '.enabled == false' >/dev/null
grep -qx 'hyprctl reload' "$TEST_LOG" || fail "off reloads Hyprland"
: >"$TEST_LOG"
"$toggle" off
[[ ! -s $TEST_LOG ]] || fail "off twice does not reload again"
"$toggle" on
[[ ! -f $flag ]] || fail "on clears the flag"
grep -qx 'hyprctl reload' "$TEST_LOG" || fail "on reloads Hyprland"
"$toggle" toggle
[[ -f $flag ]] || fail "toggle turns masking off"
"$toggle" toggle
[[ ! -f $flag ]] || fail "toggle turns masking on"
pass "the toggle persists its state and reloads Hyprland only when it changes"

# A failed reload restores the old state and fails.
if HYPRCTL_FAIL=1 "$toggle" off 2>/dev/null; then fail "off fails when Hyprland cannot reload"; fi
[[ ! -f $flag ]] || fail "a failed off keeps masking on"
"$toggle" off
if HYPRCTL_FAIL=1 "$toggle" on 2>/dev/null; then fail "on fails when Hyprland cannot reload"; fi
[[ -f $flag ]] || fail "a failed on keeps masking off"
"$toggle" on
pass "a failed reload restores the previous state and reports failure"

# Outside a session the flag is kept for the next login without calling hyprctl.
unset HYPRLAND_INSTANCE_SIGNATURE
: >"$TEST_LOG"
"$toggle" off
[[ -f $flag && ! -s $TEST_LOG ]] || fail "no session: flag set, no hyprctl call"
"$toggle" on
pass "without a session the preference is stored for the next login"

if "$toggle" bogus 2>/dev/null; then fail "unknown argument is rejected"; fi
"$ROOT/bin/monarch-menu" --tree | jq -e '
  .[] | select(.id == "setup.security.chat-privacy")
  | .action == "monarch-toggle-chat-privacy"
    and .checked == "! monarch-toggle-enabled chat-privacy-off"
' >/dev/null
pass "the Security menu exposes the chat masking state and action"
