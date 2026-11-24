#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin"

cat >"$test_root/bin/id" <<'STUB'
#!/bin/bash
printf '%s\n' "${TEST_GROUPS:-wheel}"
STUB
cat >"$test_root/bin/pacman" <<'STUB'
#!/bin/bash
[[ $1 == -Qq && $2 == ydotool && ${TEST_YDOTOOL:-false} == true ]]
STUB
cat >"$test_root/bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
cat >"$test_root/bin/gpasswd" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_GPASSWD_CALLS"
STUB
cat >"$test_root/bin/monarch-state" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_STATE_CALLS"
STUB
chmod +x "$test_root/bin/"*

if rg -n 'usermod .*input|input.*usermod' \
  "$ROOT/bin/monarch-install-gaming-xbox-controllers" \
  "$ROOT/bin/monarch-remove-gaming-xbox-controllers" >/dev/null; then
  fail "Xbox lifecycle still mutates the input group"
fi
pass "Xbox relies on seat ACLs and does not touch the input group"
