#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

QS="$ROOT/default/quickshell"

[[ -f $QS/CapturePanel.qml ]] || fail "CapturePanel.qml exists"
grep -q "^CapturePanel 1.0 CapturePanel.qml$" "$QS/qmldir" || fail "qmldir registers CapturePanel"
grep -q '"capture" ? "CapturePanel.qml"' "$QS/PanelHost.qml" || fail "the host loads the capture panel"
grep -q 'Panels: .*capture' "$ROOT/bin/monarch-panel" || fail "monarch-panel lists the capture panel"
! grep -Eq '#[0-9a-fA-F]{6}' "$QS/CapturePanel.qml" || fail "the capture panel uses theme colors, not literals"
pass "capture panel exists, is registered and uses theme colors"

# Commands live in ShellLogic; the panel closes after dispatching so the
# interactive capture is not covered.
grep -q 'Quickshell.execDetached(command)' "$QS/CapturePanel.qml" || fail "actions run detached from the logic tables"
grep -q 'target: "capture"' "$QS/CapturePanel.qml" || fail "the panel registers the capture IPC target"
grep -q 'execDetached(\["monarch-panel", "close"\])' "$QS/CapturePanel.qml" || fail "the panel closes after dispatching"
! grep -qE 'monarch-capture-[a-z-]+' "$QS/CapturePanel.qml" || fail "no command text lives in the QML"
grep -q 'pgrep", "-f", "\^gpu-screen-recorder"' "$QS/CapturePanel.qml" || fail "recording state is probed"
grep -q '"monarch-hw-webcam"' "$QS/CapturePanel.qml" || fail "the webcam variant is probed"
pass "dispatch, close and probes are wired"

if ! command -v node >/dev/null 2>&1; then
  pass "skipped capture logic checks: node is not installed"
  exit 0
fi

out=$(QS="$QS" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.QS + "/ShellLogic.js", "utf8").replace(".pragma library", "");
const L = new Function(src + "; return {panelName, captureActions, captureRecordActions, captureStopCommand, captureCommand};")();
const j = JSON.stringify;
const out = [];
out.push(L.panelName("capture") === "capture");
out.push(j(L.captureActions().map(a => a.key)) === j(["screenshot", "text", "qr", "color"]));
out.push(j(L.captureActions()[0].command) === j(["monarch-capture-screenshot"]));
out.push(L.captureRecordActions(false).length === 3 && L.captureRecordActions(true).length === 4);
out.push(L.captureRecordActions(false).every(a => a.command[0].startsWith("monarch-capture-screenrecording")));
out.push(j(L.captureStopCommand()) === j(["monarch-capture-screenrecording", "--stop-recording"]));
out.push(j(L.captureCommand("stop")) === j(L.captureStopCommand()) && j(L.captureCommand("qr")) === j(["monarch-capture-qr"]) && j(L.captureCommand("record-mic")) === j(["monarch-capture-screenrecording", "--with-desktop-audio", "--with-microphone-audio"]) && j(L.captureCommand("bogus")) === j([]));
console.log(out.map(Boolean).join(" "));
')
[[ $out == "true true true true true true true" ]] || fail "capture logic" "$out"
pass "capture actions, webcam filtering and the stop command behave"
