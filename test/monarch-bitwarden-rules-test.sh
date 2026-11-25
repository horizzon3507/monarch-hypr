#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)

python3 - "$ROOT/default/hypr/rules.lua" <<'PY'
import pathlib
import re
import sys

rules = pathlib.Path(sys.argv[1]).read_text().splitlines()
for app_id in ("Bitwarden", "bitwarden"):
  matching = []
  for line in rules:
    found = re.match(r'rule\(\{ class = "(.*?)" \}, \{(.*)\}\)$', line)
    if found and re.search(found[1], app_id):
      matching.append(found[2])
  assert any('no_screen_share = true' in rule and '+floating-window' in rule for rule in matching), \
    f"{app_id} must float and be hidden from screen sharing"

print("ok - Arch and upstream Bitwarden builds float and stay hidden from screen sharing")
PY
