#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export PATH="$TMP/bin:/usr/bin"
export OUTSET_ARGS="$TMP/outset-args"
mkdir -p "$TMP/bin"

cat >"$TMP/bin/monarch-hw-hypr-instance" <<'STUB'
#!/bin/bash
echo "stubinstance"
STUB
cat >"$TMP/bin/monarch-display-list" <<'STUB'
#!/bin/bash
printf 'eDP-1\ton\t1\t2880x1800@90\tfocused\tInternal\n'
STUB
cat >"$TMP/bin/monarch-hypr-output-set" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$OUTSET_ARGS"
STUB
chmod +x "$TMP/bin/monarch-hw-hypr-instance" "$TMP/bin/monarch-display-list" "$TMP/bin/monarch-hypr-output-set"

expect_rc() {
  local want=$1
  shift
  local rc=0
  "$@" || rc=$?
  [[ $rc -eq $want ]]
}

# Arguments are required and the scale is validated before anything runs.
expect_rc 2 "$ROOT/bin/monarch-display-scale"
expect_rc 2 "$ROOT/bin/monarch-display-scale" eDP-1
expect_rc 1 "$ROOT/bin/monarch-display-scale" eDP-1 abc
expect_rc 1 "$ROOT/bin/monarch-display-scale" eDP-1 4.5
expect_rc 1 "$ROOT/bin/monarch-display-scale" eDP-1 0.4

# An unknown output name is rejected against the live display list.
expect_rc 1 "$ROOT/bin/monarch-display-scale" HDMI-9 1.5

# A valid pair is applied through monarch-hypr-output-set.
[[ ! -f $OUTSET_ARGS ]]
"$ROOT/bin/monarch-display-scale" eDP-1 1.5
grep -Fqx "eDP-1 scale 1.5" "$OUTSET_ARGS"

echo "Display scale checks pass"
