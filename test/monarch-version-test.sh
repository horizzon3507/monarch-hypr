#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export MONARCH_PATH="$TMP/monarch"

# Without a git checkout the tools fall back to the main/stable defaults.
[[ $("$ROOT/bin/monarch-version-branch") == "main" ]]
[[ $("$ROOT/bin/monarch-version-channel") == "stable" ]]

# A checkout on dev reports the dev branch and channel.
git init -q -b dev "$MONARCH_PATH"
git -C "$MONARCH_PATH" -c user.email=test@example.com -c user.name=test \
  commit -q --allow-empty -m init
[[ $("$ROOT/bin/monarch-version-branch") == "dev" ]]
[[ $("$ROOT/bin/monarch-version-channel") == "dev" ]]

# Any other branch name passes through as its own channel.
git -C "$MONARCH_PATH" checkout -q -b feature-xyz
[[ $("$ROOT/bin/monarch-version-branch") == "feature-xyz" ]]
[[ $("$ROOT/bin/monarch-version-channel") == "feature-xyz" ]]

# A detached HEAD has no branch, so the channel is unknown.
git -C "$MONARCH_PATH" checkout -q --detach HEAD
[[ $("$ROOT/bin/monarch-version-channel") == "unknown" ]]

echo "Version branch and channel checks pass"
