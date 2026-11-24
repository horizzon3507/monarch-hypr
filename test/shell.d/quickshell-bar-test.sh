#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

QS="$ROOT/default/quickshell"

for file in Bar Workspaces Indicators Tray; do
  [[ -f $QS/$file.qml ]] || fail "$file.qml exists"
  grep -q "^$file 1.0 $file.qml$" "$QS/qmldir" || fail "qmldir registers $file"
done
grep -q '^    Bar {}$' "$QS/shell.qml" || fail "shell.qml instantiates the bar"
pass "bar components exist, are registered and the shell loads the bar"

# The bar reads layout and appearance only from the settings and theme singletons.
grep -q 'Settings.barPosition' "$QS/Bar.qml" || fail "bar follows the position setting"
grep -q 'Settings.barVisible' "$QS/Bar.qml" || fail "bar follows the visibility setting"
grep -q 'Settings.textScale' "$QS/Bar.qml" || fail "bar follows the text size setting"
! grep -Eq '#[0-9a-fA-F]{6}' "$QS"/Bar.qml "$QS"/Workspaces.qml "$QS"/Indicators.qml "$QS"/Tray.qml \
  || fail "bar components use theme colors, not literals"
pass "bar follows settings and theme without hard-coded colors"

# The clock is centered on the bar window, not placed between side widgets.
grep -q 'anchors.centerIn: parent' "$QS/Bar.qml" || fail "the clock is centered on the bar"
# Inactive workspace labels use the foreground color (dimmed by opacity only),
# never the outline color, which is nearly invisible on the bar background.
! grep -q 'Theme.outline : Theme.fg\|slot.ws !== null ? Theme.fg : Theme.outline' "$QS/Workspaces.qml" \
  || fail "inactive workspace labels stay readable"
pass "clock is centered and inactive workspace labels are readable"

if ! command -v node >/dev/null 2>&1; then
  pass "skipped bar logic checks: node is not installed"
  exit 0
fi

out=$(QS="$QS" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.QS + "/ShellLogic.js", "utf8").replace(".pragma library", "");
const L = new Function(src + "; return {workspaceSlots, workspaceDispatch, clockText, batteryPercent, batteryText, volumePercent, volumeText};")();
const j = JSON.stringify;
const out = [];
out.push(j(L.workspaceSlots([])) === "[1,2,3,4,5]");
out.push(j(L.workspaceSlots([1, 3, 9, 7, -98, 7, 2.5, "x", null])) === "[1,2,3,4,5,7,9]");
out.push(j(L.workspaceSlots(null)) === "[1,2,3,4,5]");
out.push(L.workspaceDispatch(3) === "hl.dsp.focus({ workspace = 3 })");
out.push(L.workspaceDispatch(0) === "" && L.workspaceDispatch(-1) === "" && L.workspaceDispatch(1.5) === "" && L.workspaceDispatch("a; exec x") === "");
out.push(L.clockText(new Date(2026, 10, 24, 16, 5)) === "Tue 24 Nov  16:05");
out.push(L.clockText(null) === "" && L.clockText(new Date("x")) === "");
out.push(L.batteryPercent(0.426) === 43 && L.batteryPercent(2) === 100 && L.batteryPercent(-1) === 0 && L.batteryPercent("x") === 0);
out.push(L.batteryText(0.5, true, true) === "+50%" && L.batteryText(0.5, false, true) === "50%");
out.push(L.batteryText(0.5, false, false) === "" && L.batteryText(0.1, false, false) === "low" && L.batteryText(0.5, true, false) === "charging");
out.push(L.volumePercent(0.5) === 50 && L.volumePercent(3) === 150 && L.volumePercent(NaN) === 0);
out.push(L.volumeText(0.5, true) === "muted" && L.volumeText(0.25, false) === "25%");
console.log(out.map(Boolean).join(" "));
')
[[ $out == "true true true true true true true true true true true true" ]] || fail "bar logic" "$out"
pass "workspace slots, dispatch strings, clock, battery and volume text behave"
