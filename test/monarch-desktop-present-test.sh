#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
mkdir -p "$HOME"

# No argument is an error, and an unknown entry must not be found anywhere.
if "$ROOT/bin/monarch-desktop-present"; then
  echo "monarch-desktop-present accepted a missing argument" >&2
  exit 1
fi
if "$ROOT/bin/monarch-desktop-present" alpha.desktop; then
  echo "monarch-desktop-present found an entry that does not exist" >&2
  exit 1
fi

# User applications directory counts.
mkdir -p "$HOME/.local/share/applications"
touch "$HOME/.local/share/applications/alpha.desktop"
"$ROOT/bin/monarch-desktop-present" alpha.desktop

# A ~/.nix-profile entry counts even without a user applications entry.
mkdir -p "$HOME/.nix-profile/share/applications"
touch "$HOME/.nix-profile/share/applications/beta.desktop"
"$ROOT/bin/monarch-desktop-present" beta.desktop

# A different entry is still absent.
if "$ROOT/bin/monarch-desktop-present" gamma.desktop; then
  echo "monarch-desktop-present matched an unrelated entry" >&2
  exit 1
fi

echo "Desktop entry presence checks pass"
