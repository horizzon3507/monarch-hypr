#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

QS="$ROOT/default/quickshell"
P="$QS/ThemePanel.qml"

[[ -f $P ]] || fail "ThemePanel.qml exists"
grep -q '^ThemePanel 1.0 ThemePanel.qml$' "$QS/qmldir" || fail "qmldir registers ThemePanel"
grep -q 'ThemePanel.qml' "$QS/PanelHost.qml" || fail "the host loads the theme panel"
! grep -Eq '#[0-9a-fA-F]{6}' "$P" || fail "the panel uses theme colors, not literals"
for command in 'monarch-theme-list' '"monarch-theme-mode", "get"' '"monarch-theme-mode", modelData' '"monarch-theme-set", row.modelData.name'; do
  grep -q "$command" "$P" || fail "the panel calls $command"
done
# One gate: the only place that starts the change process is act(), after mayMutate().
[[ $(grep -c 'action.running = true' "$P") == 1 ]] || fail "one place starts the action process"
awk '/function act\(/{f=1} f&&/mayMutate\(\)/{ok=1} f&&/action.running = true/{exit !ok}' "$P" || fail "act() checks the gate before it runs"
! grep -Eq 'onClicked:.*action\.running' "$P" || fail "no click handler starts a process directly"
grep -q 'Layout.rightMargin: 24' "$P" || fail "the header leaves room for the close button"
grep -q 'monarch-panel.*theme\|network, theme' "$ROOT/bin/monarch-panel" || fail "monarch-panel lists the theme panel"

if ! command -v node >/dev/null 2>&1; then
  pass "skipped theme panel logic checks: node is not installed"
  exit 0
fi

out=$(QS="$QS" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.QS + "/ShellLogic.js", "utf8").replace(".pragma library", "");
const L = new Function(src + "; return {panelName, parseThemeList, parseThemeMode};")();
const out = [];
out.push(L.panelName("theme") === "theme" && L.panelName("Theme") === "");
const t = L.parseThemeList("true\tLumon\tlumon\t/p/a.png\nfalse\tCatppuccin Latte\tcatppuccin-latte\t/p/b.png\n");
out.push(t.length === 2 && t[0].selected === true && t[1].name === "Catppuccin Latte" && t[1].selected === false);
out.push(L.parseThemeList("") === null && L.parseThemeList(null) === null && L.parseThemeList("garbage\nmaybe\tx\ty\n") === null);
out.push(L.parseThemeList("yes\tX\tx\n\ntrue\tY\ty\n").length === 1);
out.push(L.parseThemeMode("dark\n") === "dark" && L.parseThemeMode("light") === "light" && L.parseThemeMode("sepia") === "" && L.parseThemeMode(undefined) === "");
console.log(out.map(Boolean).join(" "));
')
[[ $out == "true true true true true" ]] || fail "theme panel logic" "$out"
pass "theme list and mode parsing behave"
