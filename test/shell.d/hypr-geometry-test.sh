#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"

# Fixture shaped like `hyprctl monitors -j` / `clients -j`. The field names are
# taken from Hyprland's documented output; the real 0.57.2 output is not
# confirmed here.
cat >"$test_tmp/bin/hyprctl" <<'EOF'
#!/bin/bash
case $* in
  "monitors -j")
    cat <<'JSON'
[{"name":"eDP-1","x":0,"y":0,"width":2880,"height":1800,"scale":1.5,"transform":0,"focused":true,"activeWorkspace":{"id":2}},
 {"name":"DP-1","x":1920,"y":-200,"width":1080,"height":1920,"scale":1.0,"transform":1,"focused":false,"activeWorkspace":{"id":5}}]
JSON
    ;;
  "clients -j")
    cat <<'JSON'
[{"at":[10,40],"size":[800,600],"workspace":{"id":2},"mapped":true,"hidden":false},
 {"at":[0,0],"size":[100,100],"workspace":{"id":5},"mapped":true,"hidden":false},
 {"at":[50,50],"size":[100,100],"workspace":{"id":2},"mapped":false,"hidden":false}]
JSON
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$test_tmp/bin/hyprctl"
export PATH="$test_tmp/bin:$PATH"
GEO="$ROOT/bin/monarch-hypr-geometry"

[[ $("$GEO" focused) == eDP-1 ]] || fail "focused monitor name"
pass "focused monitor name"
[[ $("$GEO" mode) == "2880 1800" ]] || fail "physical mode of the focused monitor"
pass "physical mode of the focused monitor"
[[ $("$GEO" monitors | head -1) == $'eDP-1\t0\t0\t1920\t1200\ttrue' ]] || fail "scaled logical size"
pass "scale divides the physical size"
[[ $("$GEO" monitors | tail -1) == $'DP-1\t1920\t-200\t1920\t1080\tfalse' ]] || fail "rotated output swaps its sides"
pass "a rotated output swaps its sides and keeps a negative origin"
[[ $("$GEO" windows) == "10,40 800x600" ]] || fail "windows on the focused workspace only, mapped only"
pass "only mapped windows on the focused workspace are listed"

cat >"$test_tmp/bin/hyprctl" <<'EOF'
#!/bin/bash
exit 1
EOF
[[ -z $("$GEO" windows) && -z $("$GEO" focused) ]] || fail "no compositor gives empty answers"
pass "without a compositor every answer is empty"
