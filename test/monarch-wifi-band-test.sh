#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export PATH="$TMP/bin:/usr/bin"
mkdir -p "$TMP/bin"

cat >"$TMP/bin/monarch-wifi-device" <<'STUB'
#!/bin/bash
echo "wlo1"
STUB
cat >"$TMP/bin/iw" <<'STUB'
#!/bin/bash
printf 'Connected to aa:bb:cc:dd:ee:ff (on wlo1)\n\tfreq: 2412\n'
STUB
cat >"$TMP/bin/nmcli" <<'STUB'
#!/bin/bash
case "$*" in
  *"GENERAL.CON-UUID device show"*) echo "uuid-123" ;;
  *"802-11-wireless.ssid connection show"*) echo "MyNet" ;;
  *"802-11-wireless.band connection show"*) echo "bg" ;;
  *"dev wifi list"*) printf '2412:MyNet\n5745:MyNet\n6125:OtherNet\n' ;;
esac
STUB
chmod +x "$TMP/bin/monarch-wifi-device" "$TMP/bin/iw" "$TMP/bin/nmcli"

out=$("$ROOT/bin/monarch-wifi-band")

# The link frequency names the band in use; the scan adds the other band the
# same SSID answers on and hides other networks; the stored pin is reported.
grep -Fqx $'ssid\tMyNet' <<<"$out"
grep -Fqx $'band\t2.4' <<<"$out"
grep -Fqx $'available\t2.4 5' <<<"$out"
grep -Fqx $'selected\t2.4' <<<"$out"
[[ $(wc -l <<<"$out") -eq 4 ]]

echo "Wi-Fi band status checks pass"
