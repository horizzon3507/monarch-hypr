#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
mkdir -p "$HOME"

# Without an Alacritty config there is nothing to report, and it is not an error.
[[ -z $("$ROOT/bin/monarch-font-current") ]]

# The first configured font family is reported.
mkdir -p "$HOME/.config/alacritty"
cat >"$HOME/.config/alacritty/alacritty.toml" <<'TOML'
[font.normal]
family = "JetBrainsMono Nerd Font"
TOML
[[ $("$ROOT/bin/monarch-font-current") == "JetBrainsMono Nerd Font" ]]

echo "Current font checks pass"
