#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

QS="$ROOT/default/quickshell"

[[ -f $QS/SharePanel.qml ]] || fail "SharePanel.qml exists"
grep -q "^SharePanel 1.0 SharePanel.qml$" "$QS/qmldir" || fail "qmldir registers SharePanel"
grep -q '"share" ? "SharePanel.qml"' "$QS/PanelHost.qml" || fail "the host loads the share panel"
grep -q 'Panels: .*share' "$ROOT/bin/monarch-panel" || fail "monarch-panel lists the share panel"
! grep -Eq '#[0-9a-fA-F]{6}' "$QS/SharePanel.qml" || fail "the share panel uses theme colors, not literals"
pass "share panel exists, is registered and uses theme colors"

# Commands live in ShellLogic; actions close the panel except the Wi-Fi QR
# row, which switches to the QR panel.
grep -q 'Quickshell.execDetached(command)' "$QS/SharePanel.qml" || fail "actions run detached from the logic tables"
grep -q 'target: "share"' "$QS/SharePanel.qml" || fail "the panel registers the share IPC target"
grep -q 'Logic.shareCloses' "$QS/SharePanel.qml" || fail "close behavior comes from the logic tables"
! grep -qE 'monarch-(menu-share|launch-or-focus)' "$QS/SharePanel.qml" || fail "no command text lives in the QML"
pass "dispatch and close behavior are wired"

if ! command -v node >/dev/null 2>&1; then
  pass "skipped share logic checks: node is not installed"
  exit 0
fi

out=$(QS="$QS" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.QS + "/ShellLogic.js", "utf8").replace(".pragma library", "");
const L = new Function(src + "; return {panelName, shareActions, shareCommand, shareCloses};")();
const j = JSON.stringify;
const out = [];
out.push(L.panelName("share") === "share");
out.push(j(L.shareActions().map(a => a.key)) === j(["clipboard", "file", "folder", "receive", "wifi-qr"]));
out.push(j(L.shareCommand("clipboard")) === j(["monarch-menu-share", "clipboard"]));
out.push(j(L.shareCommand("wifi-qr")) === j(["monarch-panel", "open", "wifi-qr"]));
out.push(L.shareCloses("wifi-qr") === false && L.shareCloses("clipboard") === true && L.shareCloses("bogus") === false);
out.push(j(L.shareCommand("bogus")) === j([]));
out.push(L.shareActions().every(a => a.command[0].startsWith("monarch-")));
console.log(out.map(Boolean).join(" "));
')
[[ $out == "true true true true true true true" ]] || fail "share logic" "$out"
pass "share actions, the QR panel switch and close rules behave"
