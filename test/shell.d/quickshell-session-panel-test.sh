#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

QS="$ROOT/default/quickshell"

[[ -f $QS/SessionPanel.qml ]] || fail "SessionPanel.qml exists"
grep -q "^SessionPanel 1.0 SessionPanel.qml$" "$QS/qmldir" || fail "qmldir registers SessionPanel"
grep -q '"session" ? "SessionPanel.qml"' "$QS/PanelHost.qml" || fail "the host loads the session panel"
grep -q 'Panels: .*session' "$ROOT/bin/monarch-panel" || fail "monarch-panel lists the session panel"
! grep -Eq '#[0-9a-fA-F]{6}' "$QS/SessionPanel.qml" || fail "the session panel uses theme colors, not literals"
pass "session panel exists, is registered and uses theme colors"

# The panel runs only commands from ShellLogic, detached; no command text is
# written into the QML itself.
grep -q 'Quickshell.execDetached(\[Logic.sessionCommand(key)\])' "$QS/SessionPanel.qml" || fail "actions run detached through Logic.sessionCommand"
! grep -qE 'systemctl|monarch-system-(lock|logout|reboot|shutdown)' "$QS/SessionPanel.qml" || fail "no command text lives in the QML"
grep -q 'monarch-toggle-enabled", "suspend-off"' "$QS/SessionPanel.qml" || fail "suspend follows the suspend-off toggle"
grep -q 'key === "suspend" && !suspendEnabled' "$QS/SessionPanel.qml" || fail "the panel refuses suspend when the toggle disables it"
grep -q 'target: "session"' "$QS/SessionPanel.qml" || fail "the panel registers the session IPC target"
grep -q 'function press(key: string)' "$QS/SessionPanel.qml" || fail "IPC presses go through the arm/confirm flow"
pass "actions come from ShellLogic and suspend follows the toggle"

if ! command -v node >/dev/null 2>&1; then
  pass "skipped session logic checks: node is not installed"
  exit 0
fi

out=$(QS="$QS" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.QS + "/ShellLogic.js", "utf8").replace(".pragma library", "");
const L = new Function(src + "; return {panelName, sessionActions, sessionCommand, sessionClick};")();
const j = JSON.stringify;
const out = [];
out.push(L.panelName("session") === "session");
const acts = L.sessionActions();
out.push(j(acts.map(a => a.key)) === j(["lock", "suspend", "logout", "reboot", "shutdown"]));
out.push(acts.filter(a => a.confirm).map(a => a.key).join(",") === "suspend,logout,reboot,shutdown" && !acts[0].confirm);
out.push(L.sessionCommand("lock") === "monarch-system-lock" && L.sessionCommand("shutdown") === "monarch-system-shutdown" && L.sessionCommand("bogus") === "");
out.push(j(L.sessionClick("", "lock")) === j({run: true, armed: ""}));
out.push(j(L.sessionClick("", "shutdown")) === j({run: false, armed: "shutdown"}));
out.push(j(L.sessionClick("shutdown", "shutdown")) === j({run: true, armed: ""}));
out.push(j(L.sessionClick("shutdown", "reboot")) === j({run: false, armed: "reboot"}));
out.push(j(L.sessionClick("shutdown", "bogus")) === j({run: false, armed: "shutdown"}));
console.log(out.map(Boolean).join(" "));
')
[[ $out == "true true true true true true true true true" ]] || fail "session logic" "$out"
pass "session actions, commands and the arm/confirm flow behave"
