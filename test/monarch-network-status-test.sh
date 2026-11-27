#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export PATH="$TMP/bin:/usr/bin"
export MONARCH_SYS_NET="$TMP/net"
export IP_ROUTE_OUT=""
mkdir -p "$TMP/bin" "$MONARCH_SYS_NET/eth0" "$MONARCH_SYS_NET/wlo1/wireless"

cat >"$TMP/bin/ip" <<'STUB'
#!/bin/bash
[[ -n $IP_ROUTE_OUT ]] && { printf '%s\n' "$IP_ROUTE_OUT"; exit 0; }
exit 1
STUB
cat >"$TMP/bin/nmcli" <<'STUB'
#!/bin/bash
case "$*" in
  *"dev show wlo1"*) printf 'GENERAL.STATE:100 (connected)\nGENERAL.CONNECTION:MyNet\n' ;;
  *"GENERAL.CON-UUID device show"*) echo "uuid-1" ;;
  *"802-11-wireless.ssid connection show"*) echo "MyNet" ;;
  *"dev wifi list"*) printf '*:70\n:40\n' ;;
esac
STUB
cat >"$TMP/bin/iw" <<'STUB'
#!/bin/bash
printf 'Connected to aa:bb:cc:dd:ee:ff (on wlo1)\n\tfreq: 2412\n'
STUB
chmod +x "$TMP/bin/"*

expect_rc() {
  local want=$1
  shift
  local rc=0
  "$@" || rc=$?
  [[ $rc -eq $want ]]
}

# Unknown arguments are a usage error.
expect_rc 2 "$ROOT/bin/monarch-network-status" --bogus

# No route at all reads as disconnected, with the field count preserved.
[[ $("$ROOT/bin/monarch-network-status") == $'disconnected\t\t\t' ]]

# A wired default route reports the interface as ethernet.
IP_ROUTE_OUT="1.1.1.1 via 192.168.1.1 dev eth0 src 192.168.1.10"
[[ $("$ROOT/bin/monarch-network-status") == $'ethernet\teth0\t\t' ]]

# A wireless route reports ssid, signal and frequency.
IP_ROUTE_OUT="1.1.1.1 via 192.168.1.1 dev wlo1 src 192.168.1.11"
[[ $("$ROOT/bin/monarch-network-status") == $'wifi\tMyNet\t70\t2412' ]]

echo "Network status checks pass"
