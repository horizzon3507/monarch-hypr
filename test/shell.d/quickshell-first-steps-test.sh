#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"
unset HYPRLAND_INSTANCE_SIGNATURE MONARCH_FIRST_STEPS_SHELL

QS="$ROOT/default/quickshell"
P="$QS/FirstStepsPanel.qml"

# ---- the panel (static) ----
[[ -f $P ]] || fail "FirstStepsPanel.qml exists"
grep -q '^FirstStepsPanel 1.0 FirstStepsPanel.qml$' "$QS/qmldir" || fail "qmldir registers FirstStepsPanel"
grep -q 'FirstStepsPanel.qml' "$QS/PanelHost.qml" || fail "the host loads the first-steps panel"
grep -q 'crashes, first-steps' "$ROOT/bin/monarch-panel" || fail "monarch-panel lists first-steps"
! grep -Eq '#[0-9a-fA-F]{6}' "$P" || fail "no color literals"
# Opening only marks the guide shown; checks and installs start from buttons.
grep -q 'command: \[root.script, "opened"\]' "$P" || fail "open marks the guide shown"
awk '/Component.onCompleted/{print}' "$P" | grep -vq 'install\|check' || fail "open starts no install or check"
# Detached work, so it outlives the panel when the host switches panels.
grep -q '"setsid", "-f"' "$P" || fail "visits and installs run detached"

# ---- the script on the Quickshell path (stub monarch-panel) ----
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
runtime="$tmp/runtime"
mkdir -p "$runtime/bin" "$tmp/state"
cp "$ROOT/bin/monarch-setup-first-steps" "$runtime/bin/"
cat >"$runtime/bin/monarch-panel" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_QS/calls"
case $1 in
  active) cat "$TEST_QS/active" 2>/dev/null || true ;;
  open) printf '%s\n' "$2" >"$TEST_QS/active"; [[ $2 != first-steps ]] || "$MONARCH_PATH/bin/monarch-setup-first-steps" opened ;;
  close) : >"$TEST_QS/active" ;;
esac
STUB
cat >"$runtime/bin/monarch-menu-keybindings" <<'STUB'
#!/bin/bash
printf 'keybindings\n' >>"$TEST_QS/calls"
STUB
cat >"$runtime/bin/monarch-menu" <<'STUB'
#!/bin/bash
printf 'menu %s\n' "$*" >>"$TEST_QS/calls"
STUB
cat >"$runtime/bin/noctalia" <<'STUB'
#!/bin/bash
echo "noctalia must not be called on the Quickshell path" >>"$TEST_QS/noctalia-called"
exit 1
STUB
chmod +x "$runtime"/bin/*
export MONARCH_PATH="$runtime" TEST_QS="$tmp" PATH="$runtime/bin:$PATH" MONARCH_FIRST_STEPS_SHELL=quickshell MONARCH_FIRST_STEPS_WAIT=3
export XDG_STATE_HOME="$tmp/state" XDG_DATA_HOME="$tmp/data" HOME="$tmp/home"
mkdir -p "$HOME"
: >"$tmp/active"; : >"$tmp/calls"
fs="$runtime/bin/monarch-setup-first-steps"

# open: the guide opens and the shown marker is set; nothing else is touched.
"$fs" open
grep -qx 'open first-steps' "$tmp/calls" || fail "open asks the panel host for first-steps"
[[ $("$fs" state | jq -r .shown) == true ]] || fail "open marks the guide shown"

# visit a panel destination: the guide gives way, then comes back when it closes.
: >"$tmp/calls"; : >"$tmp/active"
( sleep 1; : >"$tmp/active" ) &
"$fs" visit appearance
grep -qx 'open theme' "$tmp/calls" || fail "appearance opens the theme panel"
grep -qx 'open first-steps' "$tmp/calls" || fail "the guide returns when the panel closes"

# menu destinations do not reopen the guide.
: >"$tmp/calls"; : >"$tmp/active"
"$fs" visit shortcuts
grep -qx 'keybindings' "$tmp/calls" || fail "shortcuts run the key binding list"
! grep -q 'open first-steps' "$tmp/calls" || fail "a menu destination does not reopen the guide"

[[ ! -e $tmp/noctalia-called ]] || fail "Noctalia was called on the Quickshell path"
pass "first-steps drives the Quickshell panel host without Noctalia"

# ---- logic ----
if ! command -v node >/dev/null 2>&1; then
  pass "skipped first-steps logic checks: node is not installed"
  exit 0
fi
out=$(QS="$QS" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.QS + "/ShellLogic.js", "utf8").replace(".pragma library", "");
const L = new Function(src + "; return {panelName, firstStepsPhase, nextPhase, prevPhase, parseToolsState, parseUpdateCheck, updateView, firstStepsShortcuts, shortcutText};")();
const out = [];
out.push(L.panelName("first-steps") === "first-steps");
out.push(L.firstStepsPhase("{\"phase\":\"update\"}") === "update" && L.firstStepsPhase("{\"phase\":\"zzz\"}") === "welcome" && L.firstStepsPhase("x") === "welcome" && L.firstStepsPhase("{\"phase\":\"done\"}") === "done");
out.push(L.nextPhase("welcome") === "network" && L.nextPhase("software") === "done" && L.nextPhase("done") === "" && L.prevPhase("network") === "welcome" && L.prevPhase("welcome") === "");
const ok = {installed:{burpsuite:true,rfswift:false,seclists:false},active:"",lastResult:null,connected:true,updateResult:null};
out.push(L.parseToolsState(JSON.stringify(ok)).installed.burpsuite === true && L.parseToolsState("{}") === null && L.parseToolsState("x") === null && L.parseToolsState(JSON.stringify({installed:{},connected:"yes"})) === null);
const avail = JSON.stringify({status:"available",count:3,repositories:2,aur:1,complete:true});
out.push(L.parseUpdateCheck(avail, 0).status === "available" && L.parseUpdateCheck(avail, 1).status === "error" && L.parseUpdateCheck("x", 1).status === "error" && L.parseUpdateCheck(JSON.stringify({status:"current",count:0,complete:true}), 1).status === "current");
out.push(L.parseUpdateCheck(JSON.stringify({status:"current",count:0,complete:false}), 1).status === "error");
const tools = L.parseToolsState(JSON.stringify(ok));
const v = L.updateView(L.parseUpdateCheck(avail, 0), tools, true, true, false);
out.push(v.canUpdate === true && /3 updates/.test(v.title));
out.push(L.updateView(L.parseUpdateCheck("x", 2), tools, true, true, false).canUpdate === false);
out.push(L.updateView(null, tools, false, true, false).title === "Connection needed");
const failed = Object.assign({}, tools, {updateResult:{code:1}});
out.push(L.updateView(L.parseUpdateCheck(JSON.stringify({status:"current",count:0,complete:true}), 1), failed, true, true, false).canUpdate === true);
out.push(L.updateView(L.parseUpdateCheck(avail, 0), Object.assign({}, tools, {active:"burpsuite"}), true, true, false).canUpdate === false);
out.push(L.shortcutText("SUPER ALT + Space") === "Win + Alt + Space");
out.push(L.firstStepsShortcuts("x").length === 0 && L.firstStepsShortcuts("[]").length === 0);
console.log(out.map(Boolean).join(" "));
')
[[ $out == "true true true true true true true true true true true true true" ]] || fail "first-steps logic" "$out"
pass "first-steps phase, update and state logic behave"
