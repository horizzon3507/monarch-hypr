#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export PATH="$TMP/bin:/usr/bin"
mkdir -p "$TMP/bin"

# fc-list answers with duplicates and families the list must hide.
cat >"$TMP/bin/fc-list" <<'STUB'
#!/bin/bash
cat <<'FONTS'
JetBrains Mono
Noto Color Emoji
JetBrains Mono
Monarch Icons
Adwaita Mono
FONTS
STUB
chmod +x "$TMP/bin/fc-list"

out=$("$ROOT/bin/monarch-font-list")

# Emoji, signwriting and Monarch-internal families are filtered out.
! grep -qi 'emoji' <<<"$out"
! grep -qi 'monarch' <<<"$out"

# Remaining families are unique and sorted.
[[ $out == "$(sort -u <<<"$out")" ]]
[[ $(wc -l <<<"$out") -eq 2 ]]
grep -qx 'Adwaita Mono' <<<"$out"
grep -qx 'JetBrains Mono' <<<"$out"

echo "Font list checks pass"
