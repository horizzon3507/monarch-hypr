#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
export PATH="$test_tmp/bin:$ROOT/bin:$PATH"
export MONARCH_PATH="$ROOT"
export UPDATE_FIXTURE="$test_tmp/updates" UPDATE_DB_RECORD="$test_tmp/db"
export UPDATE_FORBIDDEN_LOG="$test_tmp/forbidden"
export TMPDIR="$test_tmp"
: >"$UPDATE_FIXTURE"

cat >"$test_tmp/bin/monarch-cmd-missing" <<'STUB'
#!/bin/bash
[[ $* == 'checkupdates fakeroot' ]] || exit 99
exit "${MISSING_COMMAND_STATUS:-1}"
STUB
cat >"$test_tmp/bin/checkupdates" <<'STUB'
#!/bin/bash
[[ $* == '--nocolor' && $LC_ALL == C ]] || exit 99
[[ -d $CHECKUPDATES_DB && $CHECKUPDATES_DB == "$TMPDIR"/tmp.* ]] || exit 99
printf '%s\n' "$CHECKUPDATES_DB" >"$UPDATE_DB_RECORD"
cat "$UPDATE_FIXTURE"
exit "${CHECKUPDATES_STATUS:-0}"
STUB
for command in git sudo pacman; do
  cat >"$test_tmp/bin/$command" <<'STUB'
#!/bin/bash
printf '%s\n' "$0 $*" >>"$UPDATE_FORBIDDEN_LOG"
exit 99
STUB
done
chmod +x "$test_tmp/bin/"*

run_check() {
  status=0
  bash "$ROOT/bin/monarch-update-available" >"$test_tmp/out" 2>"$test_tmp/err" || status=$?
}

printf 'monarch 2026.10.0-2 -> 2026.10.1-2\n' >"$UPDATE_FIXTURE"
run_check
((status == 0)) || fail "published Monarch upgrade is detected"
grep -q '2026.10.0-2 -> 2026.10.1-2' "$test_tmp/out" || fail "upgrade identifies both versions"
first_db=$(<"$UPDATE_DB_RECORD")
[[ ! -e $first_db ]] || fail "temporary database is cleaned after an available update"
pass "published Monarch upgrades use an isolated database without Git or sudo"

printf 'monarch-keyring 1 -> 2\nlinux 6.1 -> 6.2\n' >"$UPDATE_FIXTURE"
run_check
((status == 1)) || fail "unrelated package upgrades raise the Monarch badge"
[[ $(<"$UPDATE_DB_RECORD") != "$first_db" ]] || fail "checks share mutable package databases"
[[ ! -e $(<"$UPDATE_DB_RECORD") ]] || fail "temporary database is cleaned after unrelated updates"
pass "unrelated upgrades and similarly named packages do not raise the badge"

export CHECKUPDATES_STATUS=2
: >"$UPDATE_FIXTURE"
run_check
((status == 1)) || fail "checkupdates no-upgrade status is translated"
pass "no-upgrade status is distinct from a repository failure"

for check_status in 1 124 127; do
  export CHECKUPDATES_STATUS=$check_status
  run_check
  ((status == 2)) || fail "failed or timed-out checks report an error"
  [[ ! -s $test_tmp/out ]] || fail "a failed check claims availability"
  [[ ! -e $(<"$UPDATE_DB_RECORD") ]] || fail "failed checks leave a temporary database"
done
pass "repository errors, timeouts and command failures fail distinctly and clean up"

export CHECKUPDATES_STATUS=0
printf 'monarch 2026.10.0-2 ->\n' >"$UPDATE_FIXTURE"
run_check
((status == 2)) || fail "malformed Monarch update information is accepted"
pass "malformed update information cannot claim a successful check"

export MISSING_COMMAND_STATUS=0
rm "$UPDATE_DB_RECORD"
run_check
((status == 2)) || fail "missing dependencies are treated as up to date"
[[ ! -e $UPDATE_DB_RECORD ]] || fail "missing dependencies still trigger a repository check"
[[ ! -e $UPDATE_FORBIDDEN_LOG ]] || fail "checks invoke Git, sudo or the system pacman database"
pass "missing check dependencies fail before database creation"

