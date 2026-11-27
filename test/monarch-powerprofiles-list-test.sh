#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export PATH="$TMP/bin:/usr/bin"
mkdir -p "$TMP/bin"

# powerprofilesctl prints most to least power; the tool reverses that.
cat >"$TMP/ppctl-fixture" <<'FIX'
  performance:
    Driver: intel_pstate
* balanced:
    Driver: intel_pstate
  power-saver:
    Driver: intel_pstate
FIX

cat >"$TMP/bin/powerprofilesctl" <<'STUB'
#!/bin/bash
cat "$PPCTL_FIXTURE"
STUB
chmod +x "$TMP/bin/powerprofilesctl"
export PPCTL_FIXTURE="$TMP/ppctl-fixture"

expect_rc() {
  local want=$1
  shift
  local rc=0
  "$@" || rc=$?
  [[ $rc -eq $want ]]
}

# Unknown arguments are a usage error.
expect_rc 2 "$ROOT/bin/monarch-powerprofiles-list" --bogus

# Profiles come out least to most power, the reverse of powerprofilesctl.
[[ $("$ROOT/bin/monarch-powerprofiles-list") == $'power-saver\nbalanced\nperformance' ]]

# --active-state marks only the active profile.
out=$("$ROOT/bin/monarch-powerprofiles-list" --active-state)
grep -Fqx $'power-saver\t0' <<<"$out"
grep -Fqx $'balanced\t1' <<<"$out"
grep -Fqx $'performance\t0' <<<"$out"

# Without powerprofilesctl the list is empty and not an error.
rm "$TMP/bin/powerprofilesctl"
[[ -z $("$ROOT/bin/monarch-powerprofiles-list") ]]

echo "Power profile listing checks pass"
