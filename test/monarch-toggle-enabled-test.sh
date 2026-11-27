#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
mkdir -p "$HOME"

# Unknown toggle is disabled.
if "$ROOT/bin/monarch-toggle-enabled" nightlight; then
  echo "monarch-toggle-enabled reported an absent flag as enabled" >&2
  exit 1
fi

# The flag file under the toggles state directory enables exactly that toggle.
mkdir -p "$HOME/.local/state/monarch/toggles"
touch "$HOME/.local/state/monarch/toggles/nightlight"
"$ROOT/bin/monarch-toggle-enabled" nightlight
if "$ROOT/bin/monarch-toggle-enabled" dnd; then
  echo "monarch-toggle-enabled conflated two different toggles" >&2
  exit 1
fi

echo "Toggle flag checks pass"
