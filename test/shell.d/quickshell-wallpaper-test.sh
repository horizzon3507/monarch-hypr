#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

QS="$ROOT/default/quickshell"
QML="$QS/Wallpaper.qml"

[[ -f $QML ]] || fail "Wallpaper.qml exists"
grep -q '^Wallpaper 1.0 Wallpaper.qml$' "$QS/qmldir" || fail "qmldir registers Wallpaper"
grep -q '^    Wallpaper {}$' "$QS/shell.qml" || fail "shell.qml instantiates the wallpaper"
pass "wallpaper component exists, is registered and loaded by the shell"

# Background layer on every screen, no input, no space taken, and the contract
# with monarch-wallpaper-sync: wallpaper.json, rev in the URL, no image cache.
grep -q 'model: Quickshell.screens' "$QML" || fail "one wallpaper window per screen"
grep -q 'WlrLayershell.layer: WlrLayer.Background' "$QML" || fail "wallpaper is on the background layer"
grep -q 'exclusionMode: ExclusionMode.Ignore' "$QML" || fail "wallpaper takes no screen space"
grep -q 'mask: Region {}' "$QML" || fail "wallpaper takes no input"
grep -q 'fillMode: Image.PreserveAspectCrop' "$QML" || fail "wallpaper covers the screen like hyprpaper cover"
grep -q 'cache: false' "$QML" || fail "image cache is off so a new rev reloads"
grep -q 'current/wallpaper.json' "$QML" || fail "state comes from current/wallpaper.json"
grep -q 'XDG_CONFIG_HOME' "$QML" || fail "state path honors XDG_CONFIG_HOME like the sync"
grep -q 'running: root.state.path === ""' "$QML" || fail "a state file that does not exist yet is retried"
grep -q 'MONARCH_WALLPAPER_STATE' "$QML" || fail "state path can be overridden"
grep -q 'color: Theme.bg' "$QML" || fail "missing wallpaper falls back to the theme background"
! grep -q 'hyprctl\|hyprpaper' "$QML" || fail "wallpaper does not call hyprpaper"
! grep -Eq '#[0-9a-fA-F]{6}' "$QML" || fail "wallpaper uses theme colors"
pass "wallpaper is a per-screen background layer with no input, following the sync contract"

if ! command -v node >/dev/null 2>&1; then
  pass "skipped wallpaper logic checks: node is not installed"
  exit 0
fi

out=$(QS="$QS" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.QS + "/ShellLogic.js", "utf8").replace(".pragma library", "");
const L = new Function(src + "; return {parseWallpaperState, wallpaperUrl, wallpaperStatus};")();
const j = JSON.stringify;
const out = [];
const empty = j({path: "", rev: "0"});
// state: absolute path only; anything else is no wallpaper
out.push(j(L.parseWallpaperState("")) === empty && j(L.parseWallpaperState("{")) === empty && j(L.parseWallpaperState("null")) === empty);
out.push(j(L.parseWallpaperState("[]")) === empty && j(L.parseWallpaperState("{\"path\": 5, \"rev\": 1}")) === empty);
out.push(j(L.parseWallpaperState("{\"path\": \"relative/a.png\", \"rev\": 1}")) === empty);
out.push(j(L.parseWallpaperState("{\"path\": \"\", \"rev\": 1}")) === empty);
out.push(j(L.parseWallpaperState("{\"path\": \"/a/b.png\", \"rev\": 7}")) === j({path: "/a/b.png", rev: "7"}));
// rev keeps every digit of an epoch-nanosecond value (past 2^53) and separates close values
const a = L.parseWallpaperState("{\"path\": \"/a.png\", \"rev\": 1700000000000000001}").rev;
const b = L.parseWallpaperState("{\"path\": \"/a.png\", \"rev\": 1700000000000000002}").rev;
out.push(a === "1700000000000000001" && b === "1700000000000000002" && a !== b);
out.push(L.parseWallpaperState("{\"path\": \"/a.png\"}").rev === "0" && L.parseWallpaperState("{\"path\": \"/a.png\", \"rev\": \"x\"}").rev === "0");
// url: each segment percent-encoded, rev is the cache key
out.push(L.wallpaperUrl({path: "/a/b.png", rev: "3"}) === "file:///a/b.png?rev=3");
out.push(L.wallpaperUrl({path: "/tmp/wall one \u00e9#a b?.png", rev: "3"}) === "file:///tmp/wall%20one%20%C3%A9%23a%20b%3F.png?rev=3");
out.push(L.wallpaperUrl({path: "", rev: "1"}) === "" && L.wallpaperUrl({path: "rel", rev: "1"}) === "" && L.wallpaperUrl(null) === "");
out.push(L.wallpaperUrl({path: "/a.png", rev: "1"}) !== L.wallpaperUrl({path: "/a.png", rev: "2"}));
// outcome names
out.push(L.wallpaperStatus("", false, false) === "missing" && L.wallpaperStatus("u", true, false) === "ok");
out.push(L.wallpaperStatus("u", false, true) === "loading" && L.wallpaperStatus("u", false, false) === "error");
console.log(out.map(Boolean).join(" "));
')
expected=$(printf 'true %.0s' $(seq 1 13)); expected=${expected% }
[[ $out == "$expected" ]] || fail "wallpaper logic" "$out"
pass "wallpaper state, URL encoding with rev, and status names behave"
