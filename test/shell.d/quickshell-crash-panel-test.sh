#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

QS="$ROOT/default/quickshell"
P="$QS/CrashPanel.qml"

[[ -f $P ]] || fail "CrashPanel.qml exists"
grep -q '^CrashPanel 1.0 CrashPanel.qml$' "$QS/qmldir" || fail "qmldir registers CrashPanel"
grep -q 'CrashPanel.qml' "$QS/PanelHost.qml" || fail "the host loads the crash panel"
! grep -Eq '#[0-9a-fA-F]{6}' "$P" || fail "no color literals"
for command in '"monarch-crash-history", "list", "--json"' '"monarch-crash-history", "report", id' '"monarch-crash-history", "export", selected'; do
  grep -q "$command" "$P" || fail "the panel calls $command"
done
# Nothing is sent from the panel: it only reads, and saves locally through the helper.
! grep -Eq 'crash-submit|curl|mailto|xdg-open' "$P" || fail "the panel sends nothing"
[[ $(grep -c 'action.running = true' "$P") == 1 ]] || fail "one place starts the action process"
awk '/function act\(/{f=1} f&&/mayMutate\(\)/{ok=1} f&&/action.running = true/{exit !ok}' "$P" || fail "act() checks the gate before it runs"
! grep -Eq 'onClicked:.*action\.running' "$P" || fail "no click handler starts a process directly"
grep -q 'function scrollBy' "$P" && grep -q 'visible: rows.contentHeight > rows.height' "$P" || fail "keyboard scroll and a scroll track exist"
grep -q 'Layout.rightMargin: 24' "$P" || fail "the header leaves room for the close button"
grep -q 'background, crashes' "$ROOT/bin/monarch-panel" || fail "monarch-panel lists the crash panel"

if ! command -v node >/dev/null 2>&1; then
  pass "skipped crash panel logic checks: node is not installed"
  exit 0
fi

out=$(QS="$QS" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.QS + "/ShellLogic.js", "utf8").replace(".pragma library", "");
const L = new Function(src + "; return {panelName, parseCrashList, parseExportPath};")();
const id = "0123456789abcdef0123456789abcdef:123:456";
const out = [];
out.push(L.panelName("crashes") === "crashes");
const r = L.parseCrashList(JSON.stringify({crashes: [{id, application: "foot", date: "2026-11-24 20:00 UTC", signal: "SIGSEGV", core: "present"}, {id: "bad"}, null, {id: 5}, {id: id.replace("123:", "9:"), application: ""}], limit: 100, hasMore: true}));
out.push(r.crashes.length === 2 && r.crashes[0].application === "foot" && r.crashes[1].application === "unknown" && r.hasMore === true);
out.push(L.parseCrashList("nope") === null && L.parseCrashList("{}") === null && L.parseCrashList("") === null && L.parseCrashList("null") === null);
out.push(L.parseCrashList(JSON.stringify({crashes: []})).crashes.length === 0);
out.push(L.parseExportPath("{\"path\":\"/home/u/r.txt\"}") === "/home/u/r.txt" && L.parseExportPath("{\"path\":\"rel\"}") === "" && L.parseExportPath("x") === "");
console.log(out.map(Boolean).join(" "));
')
[[ $out == "true true true true true" ]] || fail "crash panel logic" "$out"
pass "crash list and export parsing behave"
