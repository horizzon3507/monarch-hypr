#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

QS="$ROOT/default/quickshell"

[[ -f $QS/TogglePanel.qml ]] || fail "TogglePanel.qml exists"
grep -q "^TogglePanel 1.0 TogglePanel.qml$" "$QS/qmldir" || fail "qmldir registers TogglePanel"
grep -q '"toggles" ? "TogglePanel.qml"' "$QS/PanelHost.qml" || fail "the host loads the toggle panel"
grep -q 'Panels: .*toggles' "$ROOT/bin/monarch-panel" || fail "monarch-panel lists the toggle panel"
! grep -Eq '#[0-9a-fA-F]{6}' "$QS/TogglePanel.qml" || fail "the toggle panel uses theme colors, not literals"
pass "toggle panel exists, is registered and uses theme colors"

# Commands live in ShellLogic; state comes from each toggle's own status
# command and a click re-reads after dispatching.
grep -q 'Quickshell.execDetached(action)' "$QS/TogglePanel.qml" || fail "actions run detached from the logic tables"
grep -q 'target: "toggles"' "$QS/TogglePanel.qml" || fail "the panel registers the toggles IPC target"
grep -q 'Logic.parseToggleStatus' "$QS/TogglePanel.qml" || fail "rows read state through parseToggleStatus"
grep -q 'reprobeTimer' "$QS/TogglePanel.qml" || fail "a click re-reads the toggles after dispatching"
! grep -qE 'monarch-toggle-[a-z-]+' "$QS/TogglePanel.qml" || fail "no command text lives in the QML"
pass "dispatch, status reads and re-probing are wired"

if ! command -v node >/dev/null 2>&1; then
  pass "skipped toggle logic checks: node is not installed"
  exit 0
fi

out=$(QS="$QS" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.QS + "/ShellLogic.js", "utf8").replace(".pragma library", "");
const L = new Function(src + "; return {panelName, togglesAvailable, toggleProbes, toggleAction, toggleStatus, parseToggleStatus};")();
const j = JSON.stringify;
const out = [];
out.push(L.panelName("toggles") === "toggles");
out.push(j(L.togglesAvailable({}).map(t => t.key)) === j(["nightlight", "idle", "notifications", "bar"]));
out.push(L.togglesAvailable({battery: true, touchpad: true, touchscreen: true}).length === 7);
out.push(L.togglesAvailable({battery: false, touchpad: true}).map(t => t.key).join(",") === "nightlight,idle,notifications,bar,touchpad");
out.push(j(L.toggleProbes().map(p => p.key)) === j(["battery", "touchpad", "touchscreen"]));
out.push(j(L.toggleAction("nightlight")) === j(["monarch-toggle-nightlight"]) && j(L.toggleStatus("nightlight")) === j(["monarch-toggle-nightlight", "status"]));
out.push(j(L.toggleAction("bogus")) === j([]) && j(L.toggleStatus("bogus")) === j([]));
out.push(L.parseToggleStatus("{\"enabled\":true}", 0) === true && L.parseToggleStatus("{\"enabled\":false}", 0) === false && L.parseToggleStatus("junk", 0) === null && L.parseToggleStatus("{\"enabled\":true}", 1) === null);
console.log(out.map(Boolean).join(" "));
')
[[ $out == "true true true true true true true true" ]] || fail "toggle logic" "$out"
pass "toggle table, hardware gating and status parsing behave"
