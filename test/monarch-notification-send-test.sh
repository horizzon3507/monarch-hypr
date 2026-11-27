#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export PATH="$TMP/bin:/usr/bin"
export NOTIFY_ARGS="$TMP/notify-args"
export ACTION_RAN="$TMP/action-ran"
mkdir -p "$TMP/bin"

cat >"$TMP/bin/notify-send" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_ARGS"
[[ $NOTIFY_ACTION_REPLY == default ]] && echo default
exit 0
STUB

# Run the detached action handler synchronously so the test can observe it.
cat >"$TMP/bin/setsid" <<'STUB'
#!/bin/bash
[[ $1 == --fork ]] && shift
exec "$@"
STUB

cat >"$TMP/bin/monarch-stub-action" <<'STUB'
#!/bin/bash
touch "$ACTION_RAN"
STUB

chmod +x "$TMP/bin/notify-send" "$TMP/bin/setsid" "$TMP/bin/monarch-stub-action"
export NOTIFY_ACTION_REPLY=""

expect_rc() {
  local want=$1
  shift
  local rc=0
  "$@" || rc=$?
  [[ $rc -eq $want ]]
}

# A headline is required, an unknown option after the description is an
# error (a second positional is the description), dangling values are errors,
# and an action command must arrive as separate arguments.
expect_rc 1 "$ROOT/bin/monarch-notification-send"
expect_rc 1 "$ROOT/bin/monarch-notification-send" "Hi" "desc" --bogus
expect_rc 1 "$ROOT/bin/monarch-notification-send" -u
expect_rc 1 "$ROOT/bin/monarch-notification-send" "Hi" --action Open "monarch-update --now"

# A plain headline goes out under the Monarch app name.
"$ROOT/bin/monarch-notification-send" "Hello there"
grep -Fqx -- "--app-name=Monarch -- Hello there" "$NOTIFY_ARGS"

# A glyph prefixes the headline and the description is indented under it.
: >"$NOTIFY_ARGS"
"$ROOT/bin/monarch-notification-send" -g "X" "Reminder" "5 minutes are up"
grep -Fqx -- "--app-name=Monarch -- X    Reminder       5 minutes are up" "$NOTIFY_ARGS"

# An action defaults to a persistent notification and runs its command when
# the notification daemon answers with the default action.
: >"$NOTIFY_ARGS"
NOTIFY_ACTION_REPLY=default "$ROOT/bin/monarch-notification-send" "Update ready" --action Open monarch-stub-action
grep -qF -- "--expire-time=0" "$NOTIFY_ARGS"
grep -qF -- "--action=default=Open" "$NOTIFY_ARGS"
[[ -f $ACTION_RAN ]]

echo "Notification send checks pass"
