#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

QS="$ROOT/default/quickshell"

[[ -f $QS/NetworkPanel.qml ]] || fail "NetworkPanel.qml exists"
grep -q '^NetworkPanel 1.0 NetworkPanel.qml$' "$QS/qmldir" || fail "qmldir registers NetworkPanel"
grep -q 'NetworkPanel.qml' "$QS/PanelHost.qml" || fail "the host loads the network panel"
! grep -Eq '#[0-9a-fA-F]{6}' "$QS/NetworkPanel.qml" || fail "the panel uses theme colors, not literals"
# State and actions go through the existing Monarch commands, not nmcli or D-Bus.
for command in 'monarch-wifi-panel", "list' 'monarch-wifi-join' '"monarch-wifi-panel", "forget"' '"monarch-wifi-panel", "disconnect"' 'monarch-toggle-wifi'; do
  grep -q "$command" "$QS/NetworkPanel.qml" || fail "the panel calls $command"
done
! grep -q 'nmcli\|password-stdin\|TextInput' "$QS/NetworkPanel.qml" || fail "the panel collects no credentials and does not call nmcli"
pass "the network panel is registered, themed and uses the Monarch commands only"

if ! command -v node >/dev/null 2>&1; then
  pass "skipped network panel logic checks: node is not installed"
  exit 0
fi

out=$(QS="$QS" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.QS + "/ShellLogic.js", "utf8").replace(".pragma library", "");
const L = new Function(src + "; return {panelName, parseWifiSnapshot, wifiRowAction, wifiHeader};")();
const row = (o) => Object.assign({key: "k", ssid: "Net", security: "WPA2", signal: 70, connected: false, saved: false, uuid: "", device: "wlan0", connecting: false}, o);
const snap = (nets, extra) => JSON.stringify(Object.assign({enabled: true, present: true, networks: nets}, extra));
const out = [];
out.push(L.panelName("network") === "network" && L.panelName("Network") === "");
const parsed = L.parseWifiSnapshot(snap([row({ssid: "A", signal: 250}), row({ssid: ""}), {ssid: 5}, null, row({ssid: "B", signal: "x", saved: "yes"})]));
out.push(parsed.networks.length === 2 && parsed.networks[0].signal === 100 && parsed.networks[1].signal === 0 && parsed.networks[1].saved === false);
out.push(L.parseWifiSnapshot("nope") === null && L.parseWifiSnapshot("{}") === null && L.parseWifiSnapshot("null") === null && L.parseWifiSnapshot("") === null);
out.push(L.parseWifiSnapshot(JSON.stringify({enabled: "yes", present: true, networks: []})) === null && L.parseWifiSnapshot(JSON.stringify({enabled: true, present: 1, networks: []})) === null && L.parseWifiSnapshot(JSON.stringify({networks: []})) === null);
out.push(L.parseWifiSnapshot(snap([], {present: false})).present === false);
out.push(L.wifiRowAction(row({connected: true, uuid: "u"})) === "disconnect" && L.wifiRowAction(row({connected: true})) === "");
out.push(L.wifiRowAction(row({saved: true})) === "join" && L.wifiRowAction(row({security: "open"})) === "join");
out.push(L.wifiRowAction(row({})) === "credentials" && L.wifiRowAction(row({security: "802.1X"})) === "credentials");
out.push(L.wifiRowAction(row({connecting: true})) === "" && L.wifiRowAction(null) === "");
out.push(L.wifiHeader(null) === "Wi-Fi status unavailable");
out.push(L.wifiHeader(L.parseWifiSnapshot(snap([], {present: false}))) === "No Wi-Fi adapter");
out.push(L.wifiHeader(L.parseWifiSnapshot(snap([], {enabled: false}))) === "Wi-Fi is off");
out.push(L.wifiHeader(L.parseWifiSnapshot(snap([row({ssid: "Home", connected: true})]))) === "Connected to Home");
out.push(L.wifiHeader(L.parseWifiSnapshot(snap([row({})]))) === "Not connected" && L.wifiHeader(L.parseWifiSnapshot(snap([]))) === "No networks in range");
console.log(out.map(Boolean).join(" "));
')
[[ $out == "true true true true true true true true true true true true true true" ]] || fail "network panel logic" "$out"
pass "snapshot parsing, row actions and the header text behave"
