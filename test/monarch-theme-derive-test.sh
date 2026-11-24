#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/shell.d/base-test.sh"

DERIVE="$ROOT/default/monarch/theme-derive.py"
PALETTES="$ROOT/config/monarch/palettes"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Every shipped palette derives in both modes it has, with only valid colors.
for palette in "$PALETTES"/*.json; do
  name=$(basename "$palette" .json)
  python3 "$DERIVE" "$palette" >"$TMP/out.json" 2>"$TMP/err" || fail "$name derives" "$(<"$TMP/err")"
  python3 - "$palette" "$TMP/out.json" "$name" <<'PY' || fail "$name output is well formed"
import json, re, sys
palette = json.load(open(sys.argv[1]))
out = json.load(open(sys.argv[2]))
hexre = re.compile(r"^#[0-9a-f]{6}$")
for variant in ("dark", "light"):
    assert (variant in palette) == (variant in out), "%s: variant %s" % (sys.argv[3], variant)
for variant, roles in out.items():
    assert len(roles) >= 40, "%s %s: only %d roles" % (sys.argv[3], variant, len(roles))
    for role, value in roles.items():
        assert hexre.match(value), "%s %s %s=%r" % (sys.argv[3], variant, role, value)
PY
done
pass "every shipped palette derives valid six-digit colors in each mode it has"

# Derived foregrounds read on their backgrounds.
python3 - "$DERIVE" "$PALETTES" <<'PY' || fail "derived foreground pairs reach 4.5:1"
import glob, importlib.util, json, sys
spec = importlib.util.spec_from_file_location("derive", sys.argv[1])
d = importlib.util.module_from_spec(spec); spec.loader.exec_module(d)
bad = []
for path in sorted(glob.glob(sys.argv[2] + "/*.json")):
    for variant, roles in d.derive(json.load(open(path))).items():
        for accent in ("primary", "secondary", "tertiary", "error"):
            for fg, bg in (("on_%s_container" % accent, "%s_container" % accent), ("on_" + accent, accent)):
                if d.contrast(roles[fg], roles[bg]) < 4.5:
                    bad.append("%s %s %s on %s = %.2f" % (path.rsplit("/", 1)[1], variant, fg, bg, d.contrast(roles[fg], roles[bg])))
if bad:
    print("\n".join(bad[:10])); sys.exit(1)
PY
pass "derived accent foregrounds reach 4.5:1 on their containers in every palette"

# Terminal colors come through, and the fallback is the surface pair.
[[ $(python3 "$DERIVE" "$PALETTES/Monarch.json" dark | jq -r '.dark | [.term_normal_red, .term_fg, .term_cursor_text] | join(",")') == "#f7768e,#a9b1d6,#1a1b26" ]] || fail "terminal colors are read from the palette"
printf '%s' '{"dark":{"mSurface":"#101010","mOnSurface":"#eeeeee","mSurfaceVariant":"#202020","mOnSurfaceVariant":"#cccccc","mOutline":"#444444","mPrimary":"#3366ff","mOnPrimary":"#ffffff","mSecondary":"#aa66ff","mOnSecondary":"#000000","mTertiary":"#66aaff","mOnTertiary":"#000000","mError":"#ff3355","mOnError":"#000000"}}' >"$TMP/min.json"
[[ $(python3 "$DERIVE" "$TMP/min.json" | jq -r '.dark | [.term_normal_red, .term_fg, .term_bg] | join(",")') == "#eeeeee,#eeeeee,#101010" ]] || fail "a palette without terminal colors falls back to the surface pair"
pass "terminal colors are read, with a fallback to the surface pair"

# Deterministic, and one mode on request.
python3 "$DERIVE" "$PALETTES/Monarch.json" >"$TMP/a.json"
python3 "$DERIVE" "$PALETTES/Monarch.json" >"$TMP/b.json"
cmp "$TMP/a.json" "$TMP/b.json" || fail "output is deterministic"
[[ $(python3 "$DERIVE" "$PALETTES/Monarch.json" dark | jq -r 'keys | join(",")') == dark ]] || fail "one mode on request"
pass "output is deterministic and a single mode can be requested"

# Bad input is refused.
echo '{"dark":{"mSurface":"#12"}}' >"$TMP/bad.json"
! python3 "$DERIVE" "$TMP/bad.json" >/dev/null 2>&1 || fail "an invalid color is refused"
echo '{}' >"$TMP/empty.json"
! python3 "$DERIVE" "$TMP/empty.json" >/dev/null 2>&1 || fail "a palette with no mode is refused"
! python3 "$DERIVE" "$TMP/missing.json" >/dev/null 2>&1 || fail "a missing file is refused"
! python3 "$DERIVE" "$PALETTES/Monarch.json" sepia >/dev/null 2>&1 || fail "an unknown mode is refused"
pass "invalid colors, empty palettes, missing files and unknown modes are refused"
