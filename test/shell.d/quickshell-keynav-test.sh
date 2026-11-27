#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

QS="$ROOT/default/quickshell"

# The host forwards Enter to the panel; menu panels move focus with
# scrollBy() and activate it with activateFocused().
grep -q 'Keys.onReturnPressed' "$QS/PanelHost.qml" || fail "the host activates the focused row on Return"
grep -q 'activateFocused' "$QS/PanelHost.qml" || fail "the host calls the panel's activateFocused"
for panel in SessionPanel CapturePanel TogglePanel SharePanel; do
  grep -q 'function scrollBy' "$QS/$panel.qml" || fail "$panel moves focus with scrollBy"
  grep -q 'function activateFocused' "$QS/$panel.qml" || fail "$panel activates the focused row"
  grep -q 'Theme.accent : "transparent"' "$QS/$panel.qml" || fail "$panel highlights the focused row"
done
pass "keyboard focus is wired through the host and the menu panels"

# Focus moves clamp at both ends; the session panel navigates its visible
# rows only.
grep -q 'root.visibleActions' "$QS/SessionPanel.qml" || fail "the session panel navigates visible rows only"
grep -q 'model: root.rows' "$QS/CapturePanel.qml" || fail "the capture panel navigates its merged row list"
! grep -Eq '#[0-9a-fA-F]{6}' "$QS/SessionPanel.qml" "$QS/CapturePanel.qml" "$QS/TogglePanel.qml" "$QS/SharePanel.qml" || fail "focus highlight uses theme colors, not literals"
pass "focus models match what each panel shows"

if ! command -v node >/dev/null 2>&1; then
  pass "skipped focus logic checks: node is not installed"
  exit 0
fi

out=$(QS="$QS" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.QS + "/ShellLogic.js", "utf8").replace(".pragma library", "");
const L = new Function(src + "; return {moveFocus};")();
const out = [];
out.push(L.moveFocus(0, 1, 3) === 1 && L.moveFocus(1, -1, 3) === 0);
out.push(L.moveFocus(2, 1, 3) === 2 && L.moveFocus(2, 8, 3) === 2);
out.push(L.moveFocus(0, -1, 3) === 0 && L.moveFocus(0, -8, 3) === 0);
out.push(L.moveFocus(5, 1, 0) === 0 && L.moveFocus(0, 1, -2) === 0);
console.log(out.map(Boolean).join(" "));
')
[[ $out == "true true true true" ]] || fail "moveFocus" "$out"
pass "focus movement clamps at both ends and survives empty lists"
