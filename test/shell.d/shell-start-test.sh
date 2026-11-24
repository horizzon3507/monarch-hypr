#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/shell" "$TMP/home"
export HOME="$TMP/home"
# The stubs come first: the real monarch-theme-apply would otherwise shadow the
# stub and, once monarch-wallpaper exists, restart hyprpaper from a background job.
export PATH="$TMP/bin:$ROOT/bin:$PATH"
export MONARCH_PATH="$ROOT"
export MONARCH_SHELL_DIR="$TMP/shell"
export STARTED="$TMP/started"
export RUNNING="$TMP/running"
: >"$STARTED"
: >"$RUNNING"

# uwsm-app records the command it would launch; pgrep answers from $RUNNING.
cat >"$TMP/bin/uwsm-app" <<'STUB'
#!/bin/bash
[[ $1 == -t && $2 == service && $3 == -- ]] || exit 2
shift 3
printf '%s\n' "$*" >>"$STARTED"
STUB
cat >"$TMP/bin/pgrep" <<'STUB'
#!/bin/bash
[[ $1 == -x ]] && grep -qx "$2" "$RUNNING"
STUB
for stub in monarch-theme-render monarch-theme-apply; do
  printf '#!/bin/bash\nexit 0\n' >"$TMP/bin/$stub"
done
chmod +x "$TMP"/bin/*

# Without a Quickshell config the daemons still start and the gap is reported.
err=$("$ROOT/bin/monarch-shell-start" 2>&1 >/dev/null)
sleep 0.2
grep -qx hyprpaper "$STARTED" || fail "hyprpaper starts"
grep -qx mako "$STARTED" || fail "mako starts"
grep -qx swayosd-server "$STARTED" || fail "swayosd starts"
grep -qx hypridle "$STARTED" || fail "hypridle starts"
! grep -q quickshell "$STARTED" || fail "quickshell is not started without a config"
[[ $err == *"no Quickshell config"* ]] || fail "a missing Quickshell config is reported"
pass "daemons start and a missing Quickshell config is reported"

# With a config, Quickshell starts from that path.
: >"$TMP/shell/shell.qml"
: >"$STARTED"
"$ROOT/bin/monarch-shell-start"
sleep 0.2
grep -qx "quickshell --path $TMP/shell" "$STARTED" || fail "quickshell starts with the shell path"
! grep -qi waybar "$STARTED" || fail "no waybar is started"
pass "quickshell starts from the shell directory"

# Running components are left alone.
printf '%s\n' hyprpaper mako swayosd-server hypridle quickshell >"$RUNNING"
: >"$STARTED"
"$ROOT/bin/monarch-shell-start"
sleep 0.2
[[ ! -s $STARTED ]] || fail "nothing is started twice"
pass "running components are not started again"

# Restart stops Quickshell and the daemons, then starts the shell again.
: >"$TMP/calls"
cat >"$TMP/bin/pkill" <<'STUB'
#!/bin/bash
printf 'pkill %s\n' "$*" >>"$TMP_CALLS"
STUB
cat >"$TMP/bin/setsid" <<'STUB'
#!/bin/bash
printf 'setsid %s\n' "$*" >>"$TMP_CALLS"
STUB
chmod +x "$TMP/bin/pkill" "$TMP/bin/setsid"
: >"$RUNNING"
TMP_CALLS="$TMP/calls" XDG_RUNTIME_DIR="$TMP/run" "$ROOT/bin/monarch-shell-restart"
for proc in quickshell mako swayosd-server hypridle hyprpaper; do
  grep -qx "pkill -x $proc" "$TMP/calls" || fail "restart stops $proc"
done
! grep -q waybar "$TMP/calls" || fail "restart does not touch waybar"
grep -q 'monarch-shell-start' "$TMP/calls" || fail "restart starts the shell again"
pass "restart stops every component and starts the shell again"
