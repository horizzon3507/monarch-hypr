#!/bin/bash
set -euo pipefail
REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/runtime"
mkdir -p "$ROOT/bin" "$ROOT/install/helpers" "$ROOT/install/reconcile"
for file in bin/monarch-install-todo bin/monarch-remove-todo install/helpers/todo.sh install/reconcile/todo.sh; do
  cp -p "$REPO_ROOT/$file" "$ROOT/$file"
done
# Only fixture copies redirect the trusted package path. Production must not
# consult a PATH-selected backend after a privileged package transaction.
python3 - "$ROOT" "$TMP/bin/monarch-todo" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
for relative in ('install/helpers/todo.sh', 'install/reconcile/todo.sh', 'bin/monarch-remove-todo'):
    path = root / relative
    text = path.read_text()
    assert '/usr/bin/monarch-todo' in text
    path.write_text(text.replace('/usr/bin/monarch-todo', sys.argv[2]))
PY
export HOME="$TMP/home" MONARCH_PATH="$ROOT" PATH="$TMP/bin:$ROOT/bin:$REPO_ROOT/bin:$PATH"
mkdir -p "$HOME" "$TMP/bin"

cat >"$TMP/bin/monarch-todo" <<'EOF'
#!/bin/bash
[[ ${TODO_OLD:-false} != "true" ]] || exit 1
[[ ${TODO_FAIL_SETUP:-false} != "true" || $* != "setup-desktop" ]] || exit 2
printf '%s\n' "$*" >>"$HOME/todo.log"
EOF
cat >"$TMP/bin/systemctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$HOME/systemctl.log"
EOF
cat >"$TMP/bin/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF
cat >"$TMP/bin/pacman" <<'EOF'
#!/bin/bash
[[ $* == "-Q monarch-todo" ]] || exit 2
[[ ${TODO_PACKAGE_MISSING:-false} != "true" ]] || exit 1
printf 'monarch-todo %s\n' "${TODO_PACKAGE_VERSION:-0.2.0-1}"
EOF
cat >"$TMP/bin/vercmp" <<'EOF'
#!/bin/bash
[[ $2 == "0.2.0" ]] || exit 2
[[ ${VERCMP_FAIL:-false} != "true" ]] || exit 3
printf '%s\n' "$*" >>"$HOME/vercmp.log"
case $1 in
  0.1.2-1 | 0.2.0rc1-1) echo -1 ;;
  0.2.0) echo 0 ;;
  0.2.0-1 | 0.2.0-12 | 0.2.1-1 | 0.10.0-1 | 1:0.2.0-1) echo 1 ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$TMP/bin/"*
source "$ROOT/install/reconcile/todo.sh"

TODO_PACKAGE_MISSING=true monarch_reconcile_todo "$ROOT"
[[ ! -e $HOME/todo.log ]]
for version in 0.1.2-1 0.2.0rc1-1; do
  TODO_PACKAGE_VERSION="$version" monarch_reconcile_todo "$ROOT"
  [[ ! -e $HOME/todo.log ]]
done
if VERCMP_FAIL=true monarch_reconcile_todo "$ROOT"; then
  echo "version comparison failure was hidden" >&2
  exit 1
fi
[[ ! -e $HOME/todo.log ]]
echo "ok - absent/older packages never execute the backend; comparison errors stop reconciliation"

TODO_OLD=true monarch_reconcile_todo "$ROOT"
[[ ! -f $HOME/.local/share/applications/Todo.desktop ]]
echo "ok - old backends keep the old integration"

monarch_reconcile_todo "$ROOT"
monarch_reconcile_todo "$ROOT"
grep -Fqx 'setup-desktop' "$HOME/todo.log"
[[ ! -e $HOME/.local/share/applications/Todo.desktop ]]
[[ ! -e $HOME/.config/systemd/user/monarch-todo-reminders.service ]]
echo "ok - Monarch delegates optional integration and owns no desktop files"

for version in 0.2.0 0.2.0-12 0.2.1-1 0.10.0-1 1:0.2.0-1; do
  before=$(grep -c '^setup-desktop$' "$HOME/todo.log")
  TODO_PACKAGE_VERSION="$version" monarch_reconcile_todo "$ROOT"
  [[ $(grep -c '^setup-desktop$' "$HOME/todo.log") == "$((before + 1))" ]]
  [[ $(tail -n 1 "$HOME/vercmp.log") == "$version 0.2.0" ]]
done
echo "ok - 0.2.0 and newer package versions use vercmp, including releases and epochs"

[[ ! -e $ROOT/bin/monarch-launch-todo ]]
echo "ok - shortcut invokes the package directly without a Monarch launcher"

if TODO_FAIL_SETUP=true monarch_reconcile_todo "$ROOT"; then
  echo "setup failure was hidden" >&2
  exit 1
fi
echo "ok - failed setup is reported"

cat >"$TMP/bin/monarch-pkg-add" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$HOME/packages.log"
exit "${PKG_STATUS:-0}"
EOF
chmod +x "$TMP/bin/monarch-pkg-add"
"$ROOT/bin/monarch-install-todo"
grep -Fqx 'monarch-todo' "$HOME/packages.log"
! grep -q 'install/reconcile' "$ROOT/bin/monarch-install-todo"
echo "ok - installer uses current setup without depending on reconciliation"
mkdir -p "$TMP/untrusted/default/i18n" "$TMP/untrusted/install/helpers"
touch "$TMP/untrusted/default/i18n/i18n.py"
printf '%s\n' 'touch "$HOME/untrusted-helper-ran"' >"$TMP/untrusted/install/helpers/todo.sh"
MONARCH_PATH="$TMP/untrusted" "$ROOT/bin/monarch-install-todo"
[[ ! -e $HOME/untrusted-helper-ran ]]
echo "ok - installer ignores environment-selected helpers after package installation"
mkdir -p "$TMP/shadow"
printf '%s\n' '#!/bin/bash' 'touch "$HOME/shadow-backend-ran"' >"$TMP/shadow/monarch-todo"
chmod +x "$TMP/shadow/monarch-todo"
PATH="$TMP/shadow:$PATH" "$ROOT/bin/monarch-install-todo"
PATH="$TMP/shadow:$PATH" monarch_reconcile_todo "$ROOT"
[[ ! -e $HOME/shadow-backend-ran ]]
echo "ok - installer and reconciliation use the installed backend, not a PATH override"

before=$(wc -l <"$HOME/todo.log")
if PKG_STATUS=1 "$ROOT/bin/monarch-install-todo"; then
  echo "package failure was hidden" >&2
  exit 1
fi
[[ $(wc -l <"$HOME/todo.log") == "$before" ]]
if TODO_OLD=true "$ROOT/bin/monarch-install-todo"; then
  echo "installer silently accepted an unsupported backend" >&2
  exit 1
fi
echo "ok - fresh install fails explicitly on package/setup errors"

cat >"$TMP/bin/monarch-pkg-drop" <<'EOF'
#!/bin/bash
exit 9
EOF
chmod +x "$TMP/bin/monarch-pkg-drop"
if "$ROOT/bin/monarch-remove-todo"; then
  echo "failed package removal reported success" >&2
  exit 1
fi
[[ $(tail -n 1 "$HOME/todo.log") == "setup-desktop" ]]
echo "ok - failed removal restores desktop integration and keeps the package integration"

