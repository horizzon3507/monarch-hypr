#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

QS="$ROOT/default/quickshell"
IND="$QS/Indicators.qml"

# Each chip asks the command that owns its state; none reads a state file.
grep -q '"monarch-capture-screenrecording", "--status"' "$IND" || fail "recording chip asks the capture command"
grep -q '"monarch-toggle-idle", "status"' "$IND" || fail "caffeine chip asks the idle toggle"
grep -q '"monarch-toggle-notification-silencing", "status"' "$IND" || fail "dnd chip asks the notification toggle"
grep -q '"monarch-toggle-nightlight", "status"' "$IND" || fail "night light chip asks the night light toggle"
grep -q '"monarch-update-available", "--all", "--json"' "$IND" || fail "update chip asks the update check"
! grep -Eq 'runtime|\.local/state|FileView' "$IND" || fail "chips do not read state files"
! grep -Eq '#[0-9a-fA-F]{6}' "$IND" || fail "chips use theme colors"
pass "chips ask the owning commands, not state files, and use theme colors"

# Every click runs a command that exists in bin/.
for cmd in monarch-capture-screenrecording monarch-toggle-idle monarch-toggle-notification-silencing monarch-toggle-nightlight monarch-launch-floating-terminal-with-presentation monarch-update; do
  [[ -f $ROOT/bin/$cmd ]] || fail "$cmd exists in bin/"
done
grep -q -- '--stop-recording' "$ROOT/bin/monarch-capture-screenrecording" || fail "recording command can stop a recording"
grep -q '"update.monarch".*monarch-launch-floating-terminal-with-presentation --app-id=org.monarch.update monarch-update' "$ROOT/default/monarch/monarch-menu.jsonc" \
  || fail "the update chip runs the same action as the menu's update row"
pass "click actions exist and the update chip matches the menu's update action"

if ! command -v node >/dev/null 2>&1; then
  pass "skipped chip logic checks: node is not installed"
  exit 0
fi

out=$(QS="$QS" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.QS + "/ShellLogic.js", "utf8").replace(".pragma library", "");
const L = new Function(src + "; return {parseToggleStatus, parseRecordingStatus, updateChipState, updateIntervalMinutes, stateChips};")();
const j = JSON.stringify;
const on = j({enabled: true, tooltip: "x"}), off = j({enabled: false});
const out = [];
// toggle status: only exit 0 with a boolean counts; failure is unknown, never off
out.push(L.parseToggleStatus(on, 0) === true && L.parseToggleStatus(off, 0) === false);
out.push(L.parseToggleStatus(off, 1) === null && L.parseToggleStatus(on, 1) === null);
out.push(L.parseToggleStatus("", 0) === null && L.parseToggleStatus("x", 0) === null && L.parseToggleStatus(j({enabled: "true"}), 0) === null && L.parseToggleStatus("null", 0) === null);
// recording: 0 running, 1 none, anything else unknown
out.push(L.parseRecordingStatus(0) === true && L.parseRecordingStatus(1) === false);
out.push(L.parseRecordingStatus(2) === null && L.parseRecordingStatus(127) === null && L.parseRecordingStatus(undefined) === null);
// chips: only true shows; unknown and off show nothing
out.push(L.stateChips({recording: null, caffeine: null, dnd: null, nightlight: null, update: null}).length === 0);
out.push(L.stateChips({recording: false, caffeine: false, dnd: false, nightlight: false}).length === 0);
out.push(L.stateChips(null).length === 0 && L.stateChips({}).length === 0);
const all = L.stateChips({recording: true, caffeine: true, dnd: true, nightlight: true, update: {count: 3, partial: false, stale: false}});
out.push(all.map(c => c.id).join() === "recording,caffeine,dnd,nightlight,update");
out.push(all[0].urgent === true && all.slice(1).every(c => c.urgent === false));
out.push(j(all[0].action) === j(["monarch-capture-screenrecording", "--stop-recording"]));
out.push(all.every(c => Array.isArray(c.action) && c.action.length >= 1 && c.text.length > 0));
// update chip text: count, partial marker, stale marker
const upd = u => L.stateChips({update: u})[0];
out.push(upd({count: 3, partial: false, stale: false}).text === "upd 3");
out.push(upd({count: 3, partial: true, stale: false}).text === "upd \u22653");
out.push(upd({count: 3, partial: false, stale: true}).text === "upd 3?" && upd({count: 3, partial: false, stale: true}).dim === true);
out.push(L.stateChips({update: {count: 0}}).length === 0 && L.stateChips({update: {count: "3"}}).length === 0);
// update state from the check: available / current / failed
const avail = j({status: "available", count: 2, complete: true, packages: []});
const cur = j({status: "current", count: 0, complete: true});
const a = L.updateChipState(null, avail, 0);
out.push(a.count === 2 && a.partial === false && a.stale === false);
out.push(L.updateChipState(a, cur, 1) === null);
const s = L.updateChipState(a, "garbage", 2);
out.push(s.count === 2 && s.stale === true);
out.push(L.updateChipState(null, "garbage", 2) === null);
out.push(L.updateChipState(a, j({status: "error", count: null, reason: "repositories-unavailable"}), 2).stale === true);
out.push(L.updateChipState(null, j({status: "available", count: 2, complete: false, packages: []}), 0).partial === true);
// a partial current result (AUR unreadable) is a failed check, not "up to date"
out.push(L.updateChipState(a, j({status: "current", count: 0, complete: false}), 1).stale === true);
// interval: 6 h when current and last check fine, 10 min otherwise
out.push(L.updateIntervalMinutes(null, false) === 360 && L.updateIntervalMinutes(null, true) === 10 && L.updateIntervalMinutes(a, false) === 10);
console.log(out.map(Boolean).join(" "));
')
expected=$(printf 'true %.0s' $(seq 1 24)); expected=${expected% }
[[ $out == "$expected" ]] || fail "state chip logic" "$out"
pass "chips show only states read as on; unreadable states are unknown; update states and intervals are right"
