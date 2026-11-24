#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

QS="$ROOT/default/quickshell"
P="$QS/DisplayPanel.qml"

[[ -f $P ]] || fail "DisplayPanel.qml exists"
grep -q '^DisplayPanel 1.0 DisplayPanel.qml$' "$QS/qmldir" || fail "qmldir registers DisplayPanel"
grep -q 'DisplayPanel.qml' "$QS/PanelHost.qml" || fail "the host loads the display panel"
! grep -Eq '#[0-9a-fA-F]{6}' "$P" "$QS/Indicators.qml" || fail "no color literals"
for command in 'monarch-display-list' '"monarch-display-brightness", "--list"' '"monarch-display-text-size", "--current"' '"monarch-display-scale", name' '"monarch-display-brightness", name' '"monarch-display-text-size", String'; do
  grep -q "$command" "$P" || fail "the panel calls $command"
done
grep -q '"monarch-display-brightness", "--list"' "$QS/Indicators.qml" || fail "the bar reads the backlight through the Monarch command"
# One gate: the only place that starts the change process is act(), after mayMutate().
[[ $(grep -c 'action.running = true' "$P") == 1 ]] || fail "one place starts the action process"
awk '/function act\(/{f=1} f&&/mayMutate\(\)/{ok=1} f&&/action.running = true/{exit !ok}' "$P" || fail "act() checks the gate before it runs"
! grep -Eq 'onClicked:.*action\.running' "$P" || fail "no click handler starts a process directly"
grep -q 'busyNotice = ""' "$P" && [[ $(grep -c 'busyNotice = "Busy' "$P") == 1 ]] || fail "the busy hint is cleared once things settle"
grep -q 'Layout.rightMargin: 24' "$P" || fail "the header leaves room for the close button"
grep -q 'network, theme, display' "$ROOT/bin/monarch-panel" || fail "monarch-panel lists the display panel"

if ! command -v node >/dev/null 2>&1; then
  pass "skipped display panel logic checks: node is not installed"
  exit 0
fi

out=$(QS="$QS" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.QS + "/ShellLogic.js", "utf8").replace(".pragma library", "");
const L = new Function(src + "; return {panelName, parseDisplayList, parseBrightnessList, stepScale, stepBrightness, parseTextSize, stepTextSize, brightnessText};")();
const out = [];
out.push(L.panelName("display") === "display");
const d = L.parseDisplayList("eDP-1\ton\t1.5\t2880x1800@120\tfocused\tBOE Panel\nDP-2\toff\t\t\t\tDell\twith\ttab\nbad\tmaybe\t1\t\t\t\n");
out.push(d.length === 2 && d[0].scale === 1.5 && d[0].focused === true && d[1].enabled === false && d[1].scale === 0 && d[1].description === "Dell with tab");
out.push(L.parseDisplayList("") === null && L.parseDisplayList(null) === null && L.parseDisplayList("x\ty\n") === null);
const b = L.parseBrightnessList("eDP-1\t60\tbacklight\nDP-2\t150\tddc\nDP-3\tx\tddc\nHDMI-1\t30\tddc\n");
out.push(b["eDP-1"].percent === 60 && b["DP-2"] === undefined && b["DP-3"] === undefined && b["HDMI-1"].backend === "ddc");
out.push(Object.keys(L.parseBrightnessList("")).length === 0);
out.push(L.stepScale(1.5, 1) === 1.75 && L.stepScale(1.5, -1) === 1.25 && L.stepScale(1.3, 1) === 1.5 && L.stepScale(1.3, -1) === 1.25);
out.push(L.stepScale(3, 1) === 0 && L.stepScale(0.75, -1) === 0 && L.stepScale(0, 1) === 0 && L.stepScale("x", 1) === 0 && L.stepScale(1, 2) === 0);
out.push(L.stepBrightness(60, 1) === 70 && L.stepBrightness(60, -1) === 50 && L.stepBrightness(100, 1) === 100 && L.stepBrightness(10, -1) === 5 && L.stepBrightness("x", 1) === -1);
out.push(L.parseTextSize("115%\n") === 115 && L.parseTextSize("abc") === 0 && L.parseTextSize("") === 0 && L.parseTextSize(undefined) === 0);
out.push(L.stepTextSize(100, 1) === 105 && L.stepTextSize(175, 1) === 175 && L.stepTextSize(75, -1) === 75 && L.stepTextSize(0, 1) === 0);
out.push(L.brightnessText(b) === "bri 60%" && L.brightnessText({a: {percent: 30, backend: "ddc"}}) === "" && L.brightnessText({}) === "" && L.brightnessText(null) === "");
console.log(out.map(Boolean).join(" "));
')
[[ $out == "true true true true true true true true true true true" ]] || fail "display panel logic" "$out"
pass "display parsing, stepping and the bar readout behave"
