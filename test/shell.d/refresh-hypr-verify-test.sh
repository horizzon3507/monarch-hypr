#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

# monarch-refresh-hypr runs `Hyprland --verify-config` during the install, inside
# arch-chroot, where XDG_RUNTIME_DIR is not set. The stub below behaves like Hyprland
# in that respect: it fails without a usable runtime dir.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/root/default/hypr" "$tmp/home"
printf '%s\n' '-- @MONARCH_PATH@' > "$tmp/root/default/hypr/hyprland.lua"

cat > "$tmp/bin/Hyprland" <<'STUB'
#!/bin/bash
[[ -n ${XDG_RUNTIME_DIR:-} && -d $XDG_RUNTIME_DIR ]] || { echo "[ERROR] XDG_RUNTIME_DIR is not set" >&2; exit 1; }
[[ $(stat -c %a "$XDG_RUNTIME_DIR") == 700 ]] || { echo "runtime dir is not private" >&2; exit 1; }
echo "$XDG_RUNTIME_DIR" > "$STUB_SEEN"
[[ ${STUB_INVALID:-} != 1 ]] || { echo "config error" >&2; exit 1; }
STUB
chmod +x "$tmp/bin/Hyprland"

run() { # <expected rc> <description> [env...]
  local want=$1 desc=$2; shift 2
  local rc=0
  env -u XDG_RUNTIME_DIR HOME="$tmp/home" MONARCH_PATH="$tmp/root" PATH="$tmp/bin:/usr/bin:/bin" STUB_SEEN="$tmp/seen" "$@" \
    bash "$ROOT/bin/monarch-refresh-hypr" >"$tmp/out" 2>&1 || rc=$?
  [[ $rc == "$want" ]] || fail "$desc (rc $rc, wanted $want)" "$(cat "$tmp/out")"
}

rm -f "$tmp/seen"
run 0 "verify succeeds with no XDG_RUNTIME_DIR (installer chroot)"
[[ -f $tmp/seen ]] || fail "the Hyprland verify ran"
seen=$(cat "$tmp/seen")
[[ ! -e $seen ]] || fail "the temporary runtime dir is removed afterwards"
pass "chroot-like run (no XDG_RUNTIME_DIR) verifies and cleans up its runtime dir"

run 1 "an invalid config is still a hard error without XDG_RUNTIME_DIR" STUB_INVALID=1
grep -q 'config validation failed' "$tmp/out" || fail "invalid config reports the validation failure"
[[ ! -e $(cat "$tmp/seen") ]] || fail "the temporary runtime dir is removed after a failure"
pass "invalid config still fails the refresh"

mkdir -m 700 "$tmp/rt"
rm -f "$tmp/seen"
run 0 "verify succeeds with a session runtime dir" XDG_RUNTIME_DIR="$tmp/rt"
[[ $(cat "$tmp/seen") == "$tmp/rt" ]] || fail "an existing XDG_RUNTIME_DIR is used as is"
[[ -d $tmp/rt ]] || fail "an existing XDG_RUNTIME_DIR is left alone"
pass "existing XDG_RUNTIME_DIR is used untouched"
