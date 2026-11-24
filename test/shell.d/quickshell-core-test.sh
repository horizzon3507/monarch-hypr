#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

QS="$ROOT/default/quickshell"

[[ -f $QS/shell.qml ]] || fail "shell entry point exists"
grep -q 'function onValuesChanged' "$QS/shell.qml" || fail "shell logs applied settings after every load"
pass "shell entry point exists and logs applied settings"

for name in Settings Theme; do
  grep -q "^singleton $name 1.0 $name.qml$" "$QS/qmldir" || fail "qmldir registers $name"
  [[ -f $QS/$name.qml ]] || fail "$name.qml exists"
  grep -q '^pragma Singleton' "$QS/$name.qml" || fail "$name is a singleton"
done
pass "settings and theme singletons are registered"

if ! command -v node >/dev/null 2>&1; then
  pass "skipped settings logic checks: node is not installed"
  exit 0
fi

out=$(QS="$QS" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.QS + "/ShellLogic.js", "utf8").replace(".pragma library", "");
const L = new Function(src + "; return {normalize, parse, colors, parseColors};")();
const j = JSON.stringify;
const out = [];
out.push(j(L.parse("garbage")) === j({barVisible:true,barPosition:"top",batteryPercent:false,textScale:1}));
const p = L.parse(j({barPosition:"left",textScale:5,barVisible:false,batteryPercent:true,extra:1}));
out.push(j(p) === j({barVisible:false,barPosition:"top",batteryPercent:true,textScale:2}));
out.push(L.parse(j({textScale:0.1})).textScale === 0.75);
out.push(L.parse(j({textScale:"x"})).textScale === 1);
out.push(L.parse(j({barPosition:"bottom"})).barPosition === "bottom");
const c = L.parseColors(j({bg:"#ABCDEF",fg:"red",accent:5}));
out.push(c.bg === "#abcdef" && c.fg === "#e6e6ea" && c.accent === "#7aa2f7");
out.push(L.parseColors("").bg === "#101014");
console.log(out.map(Boolean).join(" "));
')
[[ $out == "true true true true true true true" ]] || fail "settings logic" "$out"
pass "settings and color parsing validate and fall back to defaults"
