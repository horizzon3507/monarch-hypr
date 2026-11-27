#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export PATH="$TMP/bin:/usr/bin"
mkdir -p "$TMP/bin"

cat >"$TMP/bin/monarch-hw-hypr-instance" <<'STUB'
#!/bin/bash
echo "stubinstance"
STUB
cat >"$TMP/bin/monarch-hypr-monitor-focused" <<'STUB'
#!/bin/bash
echo "DP-1"
STUB
cat >"$TMP/bin/hyprctl" <<'STUB'
#!/bin/bash
cat <<'JSON'
[
  {"name":"DP-1","disabled":false,"scale":1.5,"width":2560,"height":1440,"refreshRate":144.0,"make":"Dell","model":"S2721"},
  {"name":"HDMI-A-1","disabled":true,"scale":2,"width":1920,"height":1080,"refreshRate":60.0,"make":"","model":"TV"}
]
JSON
STUB
chmod +x "$TMP/bin/monarch-hw-hypr-instance" "$TMP/bin/monarch-hypr-monitor-focused" "$TMP/bin/hyprctl"

out=$("$ROOT/bin/monarch-display-list")

# An enabled output reports state, scale, mode and the focused marker; a
# disabled output stays listed with no mode. The disabled fixture uses an
# integer scale so the assertion does not depend on the jq version's
# decimal formatting.
grep -Fqx $'DP-1\ton\t1.5\t2560x1440@144\tfocused\tDell S2721' <<<"$out"
grep -Fqx $'HDMI-A-1\toff\t2\t\t\tTV' <<<"$out"
[[ $(wc -l <<<"$out") -eq 2 ]]

# Without a Hyprland instance the tool fails loudly.
cat >"$TMP/bin/monarch-hw-hypr-instance" <<'STUB'
#!/bin/bash
exit 1
STUB
rc=0
"$ROOT/bin/monarch-display-list" 2>/dev/null || rc=$?
[[ $rc -eq 1 ]]

echo "Display listing checks pass"
