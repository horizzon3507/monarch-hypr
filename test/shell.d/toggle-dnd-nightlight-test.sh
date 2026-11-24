#!/bin/bash
# Do-not-disturb is mako's do-not-disturb mode; night light has no replacement
# and says so. Neither calls Noctalia.
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat >"$tmp/bin/makoctl" <<'STUB'
#!/bin/bash
echo "makoctl $*" >>"$TEST_LOG"
modes="$TEST_MODES"
case "$1 ${2:-}" in
  "mode ") cat "$modes" ;;
  "mode -a") grep -qx "$3" "$modes" || echo "$3" >>"$modes" ;;
  "mode -r") grep -vx "$3" "$modes" >"$modes.new" || true; mv "$modes.new" "$modes" ;;
esac
STUB
printf '#!/bin/bash\necho "noctalia $*" >>"$TEST_LOG"\n' >"$tmp/bin/noctalia"
chmod +x "$tmp/bin/"*
export TEST_LOG="$tmp/log" TEST_MODES="$tmp/modes" PATH="$tmp/bin:$PATH"
printf 'default\n' >"$TEST_MODES"; : >"$TEST_LOG"
dnd="$ROOT/bin/monarch-toggle-notification-silencing"

"$dnd" status | jq -e '.enabled == false' >/dev/null || fail "dnd starts off"
"$dnd" on
"$dnd" status | jq -e '.enabled == true' >/dev/null || fail "dnd on"
grep -qx do-not-disturb "$TEST_MODES" && grep -qx default "$TEST_MODES" || fail "other mako modes kept"
"$dnd" on
[[ $(grep -c '^makoctl mode -a' "$TEST_LOG") == 1 ]] || fail "on twice adds the mode once"
"$dnd" toggle
"$dnd" status | jq -e '.enabled == false' >/dev/null || fail "toggle turns it off"
"$dnd" toggle
"$dnd" status | jq -e '.enabled == true' >/dev/null || fail "toggle turns it on"
"$dnd" off
"$dnd" status | jq -e '.enabled == false' >/dev/null || fail "dnd off"
pass "do-not-disturb follows mako's mode and keeps other modes"

night="$ROOT/bin/monarch-toggle-nightlight"
"$night" status | jq -e '.enabled == false' >/dev/null || fail "night light status"
for a in on off toggle; do
  if "$night" "$a" 2>"$tmp/err"; then fail "night light $a must not report success"; fi
  grep -q 'not available yet' "$tmp/err" || fail "night light $a gives no explanation"
done
! grep -q '^noctalia' "$TEST_LOG" || fail "Noctalia was called"
pass "night light says it is not available instead of failing silently, and Noctalia is never called (stub mako)"
