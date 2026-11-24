#!/bin/bash

set -euo pipefail
unset HYPRLAND_INSTANCE_SIGNATURE

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

bin="$TEST_ROOT/bin"
runtime="$TEST_ROOT/runtime"
home="$TEST_ROOT/home"
mkdir -p "$bin" "$runtime/bin" "$runtime/install/reconcile" "$home"
touch "$runtime/bin/monarch"
chmod +x "$runtime/bin/monarch"
for step in required-packages system user; do
  printf '%s\n' "printf '%s\\n' $step >>\"\$TEST_ROOT/steps\"" \
    >"$runtime/install/reconcile/$step.sh"
done

cat >"$bin/monarch-pkg-missing" <<'STUB'
#!/bin/bash
[[ ! -f $TEST_ROOT/installed ]]
STUB
cat >"$bin/monarch-pkg-add" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_ROOT/pkg-add-calls"
touch "$TEST_ROOT/installed"
STUB
cat >"$bin/monarch-pkg-present" <<'STUB'
#!/bin/bash
[[ $1 == noctalia-shell && -f $TEST_ROOT/noctalia-installed ]]
STUB
chmod +x "$bin"/*

reconcile() {
  TEST_ROOT="$TEST_ROOT" HOME="$home" MONARCH_RUNTIME_ROOT="$runtime" \
    PATH="$bin:/usr/bin:/bin" bash "$ROOT/bin/monarch-reconcile" "$@"
}
schema_file="$home/.local/state/monarch/schema"

# A fresh home installs the package, runs the three steps and records schema 2.
reconcile >/dev/null
[[ $(<"$TEST_ROOT/pkg-add-calls") == "monarch" ]]
[[ $(<"$TEST_ROOT/steps") == $'required-packages\nsystem\nuser' ]]
[[ $(<"$schema_file") == "2" ]]
echo "ok - a fresh install reconciles once and records the current schema"

# A current-schema home does not reinstall the package.
: >"$TEST_ROOT/steps"
reconcile >/dev/null
[[ $(wc -l <"$TEST_ROOT/pkg-add-calls") == 1 ]]
[[ $(<"$TEST_ROOT/steps") == $'required-packages\nsystem\nuser' ]]
echo "ok - a current install reconciles without reinstalling the package"

# Old or newer schemas are refused.
printf '%s\n' 1 >"$schema_file"
if reconcile >/dev/null 2>&1; then
  echo "unsupported old schema was accepted" >&2
  exit 1
fi
printf '%s\n' 3 >"$schema_file"
if reconcile >/dev/null 2>&1; then
  echo "newer schema was downgraded" >&2
  exit 1
fi
echo "ok - unsupported and newer schemas are refused"

# An old Niri/Noctalia installation is refused before anything changes.
for marker in legacy-clone noctalia-package noctalia-settings; do
  rm -f "$schema_file" "$TEST_ROOT/installed" "$TEST_ROOT/noctalia-installed"
  rm -rf "$home/.local/share/monarch" "$home/.config/noctalia"
  : >"$TEST_ROOT/steps"
  : >"$TEST_ROOT/pkg-add-calls"
  case $marker in
    legacy-clone) mkdir -p "$home/.local/share/monarch" ;;
    noctalia-package) touch "$TEST_ROOT/noctalia-installed" ;;
    noctalia-settings)
      mkdir -p "$home/.config/noctalia"
      touch "$home/.config/noctalia/settings.json"
      ;;
  esac
  if reconcile >/dev/null 2>"$TEST_ROOT/err"; then
    echo "$marker installation was accepted" >&2
    exit 1
  fi
  grep -q 'fresh installs only' "$TEST_ROOT/err"
  [[ ! -s $TEST_ROOT/pkg-add-calls && ! -s $TEST_ROOT/steps && ! -e $schema_file ]]
done
echo "ok - an older Niri/Noctalia installation is refused and left untouched"

# --complete records the schema without running steps.
rm -rf "$home/.local/share/monarch" "$home/.config/noctalia"
rm -f "$TEST_ROOT/noctalia-installed"
reconcile --complete
[[ $(<"$schema_file") == "2" ]]
echo "ok - --complete records the current schema"
