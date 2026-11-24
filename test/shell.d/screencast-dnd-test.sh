#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export TEST_SCREENCAST_DND="$test_tmp"
mkdir -p "$test_tmp/bin"

# makoctl stands in for Mako: `mode` lists active modes, -a/-r add and remove one.
cat >"$test_tmp/bin/makoctl" <<'EOF'
#!/bin/bash
[[ ! -e $TEST_SCREENCAST_DND/unavailable ]] || exit 1
case $1 in
  mode)
    if (($# == 1)); then
      [[ $(<"$TEST_SCREENCAST_DND/status") == on ]] && echo do-not-disturb
      exit 0
    fi
    case $2 in
      -a) printf '%s\n' on >"$TEST_SCREENCAST_DND/status"; printf '%s\n' on >>"$TEST_SCREENCAST_DND/calls" ;;
      -r) printf '%s\n' off >"$TEST_SCREENCAST_DND/status"; printf '%s\n' off >>"$TEST_SCREENCAST_DND/calls" ;;
    esac
    ;;
esac
EOF
chmod +x "$test_tmp/bin/"*
export PATH="$test_tmp/bin:$PATH"
source "$ROOT/bin/monarch-hypr-screencast-dnd"

start='screencast>>1,0'
stop='screencast>>0,0'

printf '%s\n' off >"$test_tmp/status"
update_shared 'workspace>>2'
[[ $shared == false && $managed == false && ! -e $test_tmp/calls ]]

update_shared "$start"
[[ $shared == true && $managed == true && $(<"$test_tmp/status") == on ]]

update_shared 'screencast>>1,1'
[[ $(<"$test_tmp/calls") == on ]]

update_shared "$stop"
[[ $shared == true && $(<"$test_tmp/status") == on ]]
update_shared 'screencast>>0,1'
[[ $shared == false && $managed == false && $(<"$test_tmp/status") == off ]]
[[ $(<"$test_tmp/calls") == $'on\noff' ]]
pass "DND follows active casts and waits for the last one to stop"

update_shared "$stop"
[[ $casts == 0 && $shared == false ]]
pass "an unmatched stop event does not go negative"

printf '%s\n' on >"$test_tmp/status"
update_shared "$start"
printf '%s\n' off >"$test_tmp/status"
sync_dnd
[[ $managed == false && $(<"$test_tmp/status") == on ]]
update_shared "$stop"
[[ $managed == false && $(<"$test_tmp/status") == on ]]
pass "DND that was already active stays active"

printf '%s\n' off >"$test_tmp/status"
touch "$test_tmp/unavailable"
update_shared "$start"
[[ $shared == true && $managed == false ]]
rm "$test_tmp/unavailable"
sync_dnd
[[ $managed == true && $(<"$test_tmp/status") == on ]]
update_shared 'broken line'
[[ $shared == true && $(<"$test_tmp/status") == on ]]
restore_dnd
[[ $managed == false && $(<"$test_tmp/status") == off ]]
pass "DND recovers after Mako starts and ignores unrelated events"

grep -qF 'monarch-screencast-dnd.service' "$ROOT/install/user/first-run/enable-user-units.sh"
grep -qF 'monarch-screencast-dnd.service' "$ROOT/install/reconcile/user.sh"
grep -qF 'monarch-hypr-screencast-dnd' "$ROOT/default/systemd/user/monarch-screencast-dnd.service"
pass "fresh installs and upgrades enable the watcher"
