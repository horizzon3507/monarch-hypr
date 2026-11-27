#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export PATH="$TMP/bin:/usr/bin"
mkdir -p "$TMP/bin"

# The default route is wired Ethernet here, so the nmcli lookup decides.
cat >"$TMP/bin/ip" <<'STUB'
#!/bin/bash
echo "1.1.1.1 via 192.168.1.1 dev eth0 src 192.168.1.10"
STUB
chmod +x "$TMP/bin/ip"

# A connected wifi device wins, including localized "connected (...)" states.
cat >"$TMP/bin/nmcli" <<'STUB'
#!/bin/bash
printf 'eth0:ethernet:connected\nwlo1:wifi:connected (externally)\n'
STUB
chmod +x "$TMP/bin/nmcli"
[[ $("$ROOT/bin/monarch-wifi-device") == "wlo1" ]]

# No connected wifi is an error.
cat >"$TMP/bin/nmcli" <<'STUB'
#!/bin/bash
printf 'eth0:ethernet:connected\nwlo1:wifi:disconnected\n'
STUB
rc=0
"$ROOT/bin/monarch-wifi-device" || rc=$?
[[ $rc -eq 1 ]]

echo "Wi-Fi device checks pass"
