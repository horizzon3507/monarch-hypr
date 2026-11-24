#!/bin/bash

set -euo pipefail
unset HYPRLAND_INSTANCE_SIGNATURE

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
cat >"$test_tmp/bin/recorder" <<'EOF'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$LOCK_TEST_CALLS"
case ${0##*/} in
  noctalia) exit "${LOCK_TEST_STATUS:-0}" ;;
  pgrep)
    [[ " $* " == *" hyprlock "* ]] || exit 1
    if [[ -n ${LOCK_TEST_PGREP_SEQ:-} ]]; then
      # One exit status per call: 1 = not running, 0 = running; the last repeats.
      read -r -a seq <"$LOCK_TEST_PGREP_SEQ"
      status=${seq[0]:-1}
      (( ${#seq[@]} > 1 )) && printf '%s\n' "${seq[*]:1}" >"$LOCK_TEST_PGREP_SEQ"
      exit "$status"
    fi
    [[ -n ${LOCK_TEST_PGREP_HYPRLOCK:-} ]] && exit 0; exit 1 ;;
  pkill) exit 1 ;;
esac
EOF
chmod +x "$test_tmp/bin/recorder"
for command in noctalia pgrep pkill sleep monarch-brightness-keyboard; do
  ln -s recorder "$test_tmp/bin/$command"
done

ROOT="$ROOT" LOCK_TEST_BIN="$test_tmp/bin" LOCK_TEST_CALLS="$test_tmp/calls" python3 - <<'PY'
import os
from pathlib import Path
import subprocess

root = Path(os.environ['ROOT'])
calls = Path(os.environ['LOCK_TEST_CALLS'])

def run(status, lock_only):
  calls.write_text('')
  env = {**os.environ, 'PATH': os.environ['LOCK_TEST_BIN'],
         'LOCK_TEST_STATUS': str(status), 'MONARCH_LOCK_ONLY': str(lock_only).lower()}
  return subprocess.run(['/bin/bash', str(root / 'bin/monarch-system-lock')],
                        env=env, capture_output=True, text=True)

for lock_only in (True, False):
  for status in (1, 127):
    result = run(status, lock_only)
    assert result.returncode == status, (status, lock_only, result.returncode)
    assert result.stderr.strip(), 'a failed lock request must have a diagnostic'
    assert 'noctalia msg session lock' in calls.read_text()
  result = run(0, lock_only)
  assert result.returncode == 0, result
  assert not result.stderr, result.stderr
  assert 'pkill -f [o]rg.monarch.screensaver' in calls.read_text()
  assert ('monarch-brightness-keyboard off' in calls.read_text()) == (not lock_only)
print('ok - lock errors survive cleanup in manual and lock-only modes')
print('ok - missing cleanup targets do not turn an accepted lock request into a failure')

Path(os.environ['LOCK_TEST_BIN'], 'noctalia').unlink()
result = run(0, True)
assert result.returncode == 127, result
assert result.stderr.strip(), 'a missing Noctalia command must not report success'
print('ok - an unavailable Noctalia command fails without contacting the desktop')

# Hyprland session: hyprlock, never Noctalia.
def run_hypr(have_lock, running, seq=None):
  calls.write_text('')
  bin_dir = Path(os.environ['LOCK_TEST_BIN'])
  for name in ('hyprlock', 'setsid'):
    link = bin_dir / name
    if link.is_symlink() or link.exists():
      link.unlink()
  if have_lock:
    (bin_dir / 'hyprlock').symlink_to('recorder')
  (bin_dir / 'setsid').symlink_to('recorder')
  env = {**os.environ, 'PATH': str(bin_dir), 'HYPRLAND_INSTANCE_SIGNATURE': 'x',
         'MONARCH_LOCK_ONLY': 'true', 'LOCK_TEST_PGREP_HYPRLOCK': '1' if running else ''}
  if seq:
    seq_file = bin_dir / 'pgrep-seq'
    seq_file.write_text(seq + '\n')
    env['LOCK_TEST_PGREP_SEQ'] = str(seq_file)
  return subprocess.run(['/bin/bash', str(root / 'bin/monarch-system-lock')], env=env, capture_output=True, text=True)

# pgrep -x hyprlock: the recorder exits 1 (not running) unless told otherwise.
r = run_hypr(False, False)
assert r.returncode == 127 and 'hyprlock is not installed' in r.stderr, r
assert 'noctalia' not in calls.read_text(), 'the Hyprland path must not call Noctalia'
r = run_hypr(True, False)
assert 'setsid -f hyprlock' in calls.read_text() and 'noctalia' not in calls.read_text(), calls.read_text()
assert r.returncode == 1 and 'did not start' in r.stderr, 'a lock that never appears is a failure, not success'
r = run_hypr(True, True)
assert r.returncode == 0 and 'setsid' not in calls.read_text() and 'noctalia' not in calls.read_text(), (r, calls.read_text())
# Starts, then dies at once: failure, not success (the stub run H1 found returning 0).
r = run_hypr(True, False, '1 0 1')
assert r.returncode == 1 and 'exited at once' in r.stderr, r
assert 'setsid -f hyprlock' in calls.read_text()
# Starts and stays: success.
r = run_hypr(True, False, '1 0 0')
assert r.returncode == 0 and not r.stderr, r
# Never appears at all: failure.
r = run_hypr(True, False, '1 1')
assert r.returncode == 1, r
print('ok - on Hyprland the lock starts hyprlock, reports a missing or failed lock, and never calls Noctalia')
PY
