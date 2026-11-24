#!/bin/bash
# The terminal working directory comes from Hyprland's active window pid.
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"
tmp=$(mktemp -d)
trap 'kill "${term:-}" 2>/dev/null || true; pkill -P "${term:-0}" 2>/dev/null || true; rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/dir" "$tmp/home"
export HOME="$tmp/home"
cat >"$tmp/bin/hyprctl" <<'STUB'
#!/bin/bash
[[ $1 == activewindow && $2 == -j ]] || exit 2
printf '{"class":"x","pid":%s}\n' "${TERM_PID:-1}"
STUB
chmod +x "$tmp/bin/hyprctl"
shell=$(readlink -f "$(command -v bash)")
grep -qs "$shell" /etc/shells || { pass "skipped: $shell is not listed in /etc/shells here"; exit 0; }
# "Terminal" process whose child is a bash in $tmp/dir.
bash -c 'cd "$1" && bash -c "sleep 20; true"; true' _ "$tmp/dir" & term=$!
export PATH="$tmp/bin:$ROOT/bin:/usr/bin:/bin"
for _ in $(seq 50); do pgrep -P "$term" >/dev/null && break; sleep 0.05; done
out=$(TERM_PID=$term monarch-cmd-terminal-cwd)
[[ $out == "$tmp/dir" ]] || fail "the cwd of the active terminal's shell is returned, got $out"
out=$(TERM_PID=99999999 monarch-cmd-terminal-cwd)
[[ $out == "$HOME" ]] || fail "an unknown pid falls back to home"
pass "terminal cwd asks hyprctl for the active window pid and falls back to home"
