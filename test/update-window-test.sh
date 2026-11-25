#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export MONARCH_PATH="$ROOT"
export PATH="$ROOT/bin:$PATH"
export MONARCH_LANGUAGE=en

action=$(monarch-menu --tree | jq -r '.[] | select(.id == "update.monarch") | .action')
[[ $action == "monarch-launch-floating-terminal-with-presentation --app-id=org.monarch.update monarch-update" ]] || {
  echo "not ok - update menu must use its dedicated window identity" >&2
  exit 1
}

grep -Fq 'rule({ class = "org.monarch.(update|agent-usage|pentest|about)" }, { float = true, center = true })' "$ROOT/default/hypr/rules.lua"
grep -Fq 'rule({ class = "org.monarch.(update|agent-usage|pentest)" }, { size = "875 600" })' "$ROOT/default/hypr/rules.lua"

echo "ok - menu opens updates in an 875 x 600 floating window"
