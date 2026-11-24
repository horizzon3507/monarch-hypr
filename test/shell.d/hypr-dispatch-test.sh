#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

# Mock-level test: checks the dispatcher expressions these helpers send, as
# documented for Hyprland's Lua API. It does not prove Hyprland accepts them.

t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin"
cat >"$t/bin/hyprctl" <<'MOCK'
#!/bin/bash
case $* in
  "clients -j") echo '[{"address":"0xaa","class":"firefox","title":"x"},{"address":"0xbb","class":"kitty","title":"y"}]' ;;
  "activewindow -j") echo "${MOCK_ACTIVE:-{\"address\":\"0xaa\",\"floating\":false,\"pinned\":false\}}" ;;
  "dispatch "*) printf "%s\n" "${2}" >>"$MOCK_LOG" ;;
esac
MOCK
printf '#!/bin/bash\n:\n' >"$t/bin/monarch-brightness-keyboard"
chmod +x "$t/bin/"*
export PATH="$t/bin:$PATH" MOCK_LOG="$t/log"

check() { grep -Fxq -- "$2" "$MOCK_LOG" || { cat "$MOCK_LOG" >&2; fail "$1: missing $2"; }; }

: >"$MOCK_LOG"
"$ROOT/bin/monarch-hypr-window-close-all"
check close-all 'hl.dsp.window.close({ window = "address:0xaa" })'
check close-all 'hl.dsp.window.close({ window = "address:0xbb" })'
check close-all 'hl.dsp.focus({ workspace = 1 })'
pass "close-all uses window.close and focus workspace"

: >"$MOCK_LOG"
"$ROOT/bin/monarch-hypr-window-pop"
check pop 'hl.dsp.window.float({ action = "toggle" })'
check pop 'hl.dsp.window.resize({ x = 875, y = 600, relative = false })'
check pop 'hl.dsp.window.center()'
check pop 'hl.dsp.window.pin({ action = "toggle" })'
pass "pop floats, resizes, centers and pins"

: >"$MOCK_LOG"
"$ROOT/bin/monarch-launch-or-focus" kitty
check focus 'hl.dsp.focus({ window = "address:0xbb" })'
pass "launch-or-focus focuses by address"

: >"$MOCK_LOG"
"$ROOT/bin/monarch-system-wake"
check wake 'hl.dsp.dpms({ action = "enable" })'
pass "system wake enables dpms"

if grep -rnE 'hyprctl dispatch (closewindow|workspace|pin|togglefloating|resizeactive|centerwindow|focuswindow|focusmonitor|dpms)\b' "$ROOT/bin" "$ROOT/config"; then
  fail "legacy hyprctl dispatch form still shipped"
fi
pass "no legacy hyprctl dispatch forms in bin or config"
