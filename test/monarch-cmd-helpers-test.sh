#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"
cat >"$TMP/bin/monarch-stub-present" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$TMP/bin/monarch-stub-present"
export PATH="$TMP/bin:/usr/bin"

# monarch-cmd-present: 0 only when every argument resolves on PATH
"$ROOT/bin/monarch-cmd-present" monarch-stub-present
"$ROOT/bin/monarch-cmd-present" monarch-stub-present bash
if "$ROOT/bin/monarch-cmd-present" monarch-stub-missing; then
  echo "monarch-cmd-present accepted a missing command" >&2
  exit 1
fi
if "$ROOT/bin/monarch-cmd-present" monarch-stub-present monarch-stub-missing; then
  echo "monarch-cmd-present ignored a missing later argument" >&2
  exit 1
fi

# monarch-cmd-missing: 0 when any argument is absent, 1 when all resolve
"$ROOT/bin/monarch-cmd-missing" monarch-stub-missing
"$ROOT/bin/monarch-cmd-missing" monarch-stub-present monarch-stub-missing
if "$ROOT/bin/monarch-cmd-missing" monarch-stub-present; then
  echo "monarch-cmd-missing reported an installed command as missing" >&2
  exit 1
fi
if "$ROOT/bin/monarch-cmd-missing" monarch-stub-present bash; then
  echo "monarch-cmd-missing reported installed commands as missing" >&2
  exit 1
fi

echo "Command availability guard checks pass"
