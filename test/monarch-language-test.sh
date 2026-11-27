#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export XDG_CONFIG_HOME="$TMP/config"
mkdir -p "$XDG_CONFIG_HOME"

expect_rc() {
  local want=$1
  shift
  local rc=0
  "$@" || rc=$?
  [[ $rc -eq $want ]]
}

# The menu list is fixed and stable.
[[ $("$ROOT/bin/monarch-language" --list) == $'auto\nen\nfr' ]]
expect_rc 2 "$ROOT/bin/monarch-language" --list extra

# Without a stored preference the effective one is auto.
[[ $("$ROOT/bin/monarch-language" --preference) == "auto" ]]

# A stored supported preference wins; anything else falls back to auto.
mkdir -p "$XDG_CONFIG_HOME/monarch"
printf 'fr\n' >"$XDG_CONFIG_HOME/monarch/language"
[[ $("$ROOT/bin/monarch-language" --preference) == "fr" ]]
printf 'klingon\n' >"$XDG_CONFIG_HOME/monarch/language"
[[ $("$ROOT/bin/monarch-language" --preference) == "auto" ]]

# Setting a language writes the preference the reader then reports.
"$ROOT/bin/monarch-language" en
[[ $(cat "$XDG_CONFIG_HOME/monarch/language") == "en" ]]
[[ $("$ROOT/bin/monarch-language" --preference) == "en" ]]

# An unknown language is a usage error.
expect_rc 2 "$ROOT/bin/monarch-language" klingon

echo "Language preference checks pass"
