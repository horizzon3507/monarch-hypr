#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

QS="$ROOT/default/quickshell"

for file in PanelHost WifiQr; do
  [[ -f $QS/$file.qml ]] || fail "$file.qml exists"
  grep -q "^$file 1.0 $file.qml$" "$QS/qmldir" || fail "qmldir registers $file"
done
grep -q '^    PanelHost {}$' "$QS/shell.qml" || fail "shell.qml instantiates the panel host"
grep -q 'target: "panel"' "$QS/PanelHost.qml" || fail "the host registers the panel IPC target"
grep -q 'WlrLayershell.layer: WlrLayer.Overlay' "$QS/PanelHost.qml" || fail "panels sit in the overlay layer"
! grep -Eq '#[0-9a-fA-F]{6}' "$QS/PanelHost.qml" "$QS/WifiQr.qml" || fail "panels use theme colors, not literals"
pass "panel host and Wi-Fi QR panel exist, are registered and use theme colors"

# The password is requested only by the deliberate click and dropped with the card.
grep -q 'monarch-wifi-qr", "--png"' "$QS/WifiQr.qml" || fail "the QR comes from monarch-wifi-qr --png"
grep -q 'monarch-wifi-password' "$QS/WifiQr.qml" || fail "the password comes from monarch-wifi-password"
! grep -q 'command: \[.*"--password"' "$QS/WifiQr.qml" || fail "the password is not read at generation"
grep -q 'Component.onDestruction: password = ""' "$QS/WifiQr.qml" || fail "the password is dropped with the card"
pass "the password is read on click only and dropped with the card"

# monarch-panel builds the IPC call and refuses anything else.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >>"$QS_CALLS"\n' >"$tmp/bin/quickshell"
chmod +x "$tmp/bin/quickshell"
export QS_CALLS="$tmp/calls" PATH="$tmp/bin:$PATH" MONARCH_SHELL_DIR=/shell
"$ROOT/bin/monarch-panel" toggle wifi-qr
"$ROOT/bin/monarch-panel" close
[[ $(<"$QS_CALLS") == $'ipc --path /shell call panel toggle wifi-qr\nipc --path /shell call panel close' ]] || fail "monarch-panel builds the IPC call" "$(<"$QS_CALLS")"
for bad in "toggle" "toggle ../x" "toggle a;b" "launch wifi-qr" ""; do
  # shellcheck disable=SC2086
  "$ROOT/bin/monarch-panel" $bad 2>/dev/null && fail "monarch-panel rejects: $bad"
done
pass "monarch-panel builds the IPC call and rejects bad input"

if ! command -v node >/dev/null 2>&1; then
  pass "skipped panel logic checks: node is not installed"
  exit 0
fi

out=$(QS="$QS" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.QS + "/ShellLogic.js", "utf8").replace(".pragma library", "");
const L = new Function(src + "; return {panelName, togglePanel, parseWifiQr, wifiSecured};")();
const j = JSON.stringify;
const out = [];
out.push(L.panelName("wifi-qr") === "wifi-qr" && L.panelName("nope") === "" && L.panelName(null) === "" && L.panelName("wifi-qr;x") === "");
out.push(L.togglePanel("", "wifi-qr") === "wifi-qr" && L.togglePanel("wifi-qr", "wifi-qr") === "" && L.togglePanel("wifi-qr", "bad") === "wifi-qr");
out.push(j(L.parseWifiQr("meta\twlan0\tWPA\t/run/x/wifi-qr-1.png\tMy\tNet")) === j({iface: "wlan0", security: "WPA", png: "/run/x/wifi-qr-1.png", ssid: "My\tNet"}));
out.push(L.parseWifiQr("") === null && L.parseWifiQr("meta\twlan0\tWPA\t\tname") === null && L.parseWifiQr("junk") === null && L.parseWifiQr(undefined) === null);
out.push(L.wifiSecured("WPA") && L.wifiSecured("WEP") && !L.wifiSecured("nopass") && !L.wifiSecured(""));
console.log(out.map(Boolean).join(" "));
')
[[ $out == "true true true true true" ]] || fail "panel logic" "$out"
pass "panel names, toggling, QR output parsing and secured detection behave"
