#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

QS="$ROOT/default/quickshell"
P="$QS/BackgroundPanel.qml"

[[ -f $P ]] || fail "BackgroundPanel.qml exists"
grep -q '^BackgroundPanel 1.0 BackgroundPanel.qml$' "$QS/qmldir" || fail "qmldir registers BackgroundPanel"
grep -q 'BackgroundPanel.qml' "$QS/PanelHost.qml" || fail "the host loads the background panel"
! grep -Eq '#[0-9a-fA-F]{6}' "$P" || fail "no color literals"
grep -q '"monarch-theme-background-list"' "$P" || fail "the panel lists through the Monarch command"
grep -q '"monarch-wallpaper", "set", row.modelData.path' "$P" || fail "the panel sets through monarch-wallpaper"
[[ $(grep -c 'action.running = true' "$P") == 1 ]] || fail "one place starts the action process"
awk '/function act\(/{f=1} f&&/mayMutate\(\)/{ok=1} f&&/action.running = true/{exit !ok}' "$P" || fail "act() checks the gate before it runs"
! grep -Eq 'onClicked:.*action\.running' "$P" || fail "no click handler starts a process directly"
grep -q 'Image.Error' "$P" && grep -q 'if (!row.broken)' "$P" || fail "an image that fails to load is not selectable"
grep -q 'function scrollBy' "$P" && grep -q 'visible: rows.contentHeight > rows.height' "$P" || fail "keyboard scroll and a scroll track exist"
grep -q 'Layout.rightMargin: 24' "$P" || fail "the header leaves room for the close button"
grep -q 'theme, display, background' "$ROOT/bin/monarch-panel" || fail "monarch-panel lists the background panel"

if ! command -v node >/dev/null 2>&1; then
  pass "skipped background panel logic checks: node is not installed"
  exit 0
fi

out=$(QS="$QS" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.QS + "/ShellLogic.js", "utf8").replace(".pragma library", "");
const L = new Function(src + "; return {panelName, parseBackgroundList};")();
const out = [];
out.push(L.panelName("background") === "background");
const r = L.parseBackgroundList("true\ta.png\t/w/a.png\t/c/1.jpg\tfalse\nfalse\tb b.jpg\t/w/b b.jpg\t/w/b b.jpg\ttrue\n");
out.push(r.length === 2 && r[0].active === true && r[1].name === "b b.jpg" && r[1].path === "/w/b b.jpg");
out.push(L.parseBackgroundList("false\tx.png\trelative/x.png\t/c\tfalse\nmaybe\ty\t/y\t/y\tfalse\ntoo\tshort\n") === null);
out.push(L.parseBackgroundList("").length === 0 && L.parseBackgroundList(null).length === 0 && L.parseBackgroundList("\n  \n").length === 0);
out.push(L.parseBackgroundList("garbage") === null && L.parseBackgroundList("{\"a\":1}") === null);
out.push(L.parseBackgroundList("false\tz.png\t/z.png\trelative\tfalse")[0].thumbnail === "");
console.log(out.map(Boolean).join(" "));
')
[[ $out == "true true true true true true" ]] || fail "background panel logic" "$out"
pass "background list parsing behaves"
