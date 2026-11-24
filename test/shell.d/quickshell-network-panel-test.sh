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
grep -q 'stale' "$QS/NetworkPanel.qml" && grep -q 'wifiRadioEnabled' "$QS/NetworkPanel.qml" || fail "the panel gates actions on a stale list"
grep -q 'ElideNone' "$QS/NetworkPanel.qml" && grep -q 'expanded = !row.expanded' "$QS/NetworkPanel.qml" || fail "the full network name is reachable through a separate control"
grep -q 'readonly property bool settled' "$QS/NetworkPanel.qml" && grep -q 'if (!settled)' "$QS/NetworkPanel.qml" || fail "actions wait for an in-flight refresh or action"
# Every state-changing path goes through the shared gate: the only places that
# start the action or radio processes are act() and toggleRadio(), and both call
# mayMutate() first. (Forget once bypassed the busy check.)
[[ $(grep -c 'action.running = true' "$QS/NetworkPanel.qml") == 1 ]] || fail "one place starts the action process"
[[ $(grep -c 'radio.running = true' "$QS/NetworkPanel.qml") == 1 ]] || fail "one place starts the radio process"
awk '/function act\(/{f=1} f&&/mayMutate\(\)/{ok=1} f&&/action.running = true/{exit !ok}' "$QS/NetworkPanel.qml" || fail "act() checks the gate before it runs"
awk '/function toggleRadio\(/{f=1} f&&/mayMutate\(\)/{ok=1} f&&/radio.running = true/{exit !ok}' "$QS/NetworkPanel.qml" || fail "toggleRadio() checks the gate before it runs"
! grep -Eq 'onClicked:.*(action|radio)\.running' "$QS/NetworkPanel.qml" || fail "no click handler starts a process directly"
grep -Eq 'visible: true' "$QS/NetworkPanel.qml" || fail "Rescan is always reachable"
! grep -q 'HoverHandler' "$QS/NetworkPanel.qml" || fail "the full name does not depend on hover"
grep -q 'listError = ""' "$QS/NetworkPanel.qml" && grep -q 'noticeText = ""' "$QS/NetworkPanel.qml" || fail "a good refresh clears the obsolete notice and list error"
grep -q 'Layout.rightMargin: 24' "$QS/NetworkPanel.qml" || fail "the header leaves room for the close button"
pass "the network panel is registered, themed and uses the Monarch commands only"

if ! command -v node >/dev/null 2>&1; then
  pass "skipped network panel logic checks: node is not installed"
  exit 0
fi

out=$(QS="$QS" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.QS + "/ShellLogic.js", "utf8").replace(".pragma library", "");
const L = new Function(src + "; return {panelName, parseWifiSnapshot, wifiRowAction, wifiHeader, wifiRadioEnabled};")();
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
const live = row({connected: true, uuid: "u"});
out.push(L.wifiRowAction(live, true) === "" && L.wifiRowAction(row({saved: true}), true) === "" && L.wifiRowAction(row({saved: true}), false) === "join");
out.push(L.wifiRadioEnabled(null, false) === false && L.wifiRadioEnabled({}, true) === false && L.wifiRadioEnabled({}, false) === true);
out.push(L.wifiHeader(null) === "Wi-Fi status unavailable");
out.push(L.wifiHeader(L.parseWifiSnapshot(snap([], {present: false}))) === "No Wi-Fi adapter");
out.push(L.wifiHeader(L.parseWifiSnapshot(snap([], {enabled: false}))) === "Wi-Fi is off");
out.push(L.wifiHeader(L.parseWifiSnapshot(snap([row({ssid: "Home", connected: true})]))) === "Connected to Home");
out.push(L.wifiHeader(L.parseWifiSnapshot(snap([row({})]))) === "Not connected" && L.wifiHeader(L.parseWifiSnapshot(snap([]))) === "No networks in range");
console.log(out.map(Boolean).join(" "));
')
[[ $out == "true true true true true true true true true true true true true true true true" ]] || fail "network panel logic" "$out"
pass "snapshot parsing, row actions and the header text behave"
