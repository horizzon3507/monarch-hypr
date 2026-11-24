#!/bin/bash

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
cat >"$test_tmp/bin/recorder" <<'EOF'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$LOCK_TEST_CALLS"
case ${0##*/} in
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
for command in pgrep pkill sleep monarch-brightness-keyboard; do
  ln -s recorder "$test_tmp/bin/$command"
done

ROOT="$ROOT" LOCK_TEST_BIN="$test_tmp/bin" LOCK_TEST_CALLS="$test_tmp/calls" python3 - <<'PY'
import os
from pathlib import Path
import subprocess

root = Path(os.environ['ROOT'])
calls = Path(os.environ['LOCK_TEST_CALLS'])
bin_dir = Path(os.environ['LOCK_TEST_BIN'])

def run(have_lock, running, seq=None, lock_only=True):
  calls.write_text('')
  for name in ('hyprlock', 'setsid'):
    (bin_dir / name).unlink(missing_ok=True)
  if have_lock:
    (bin_dir / 'hyprlock').symlink_to('recorder')
  (bin_dir / 'setsid').symlink_to('recorder')
  env = {**os.environ, 'PATH': str(bin_dir), 'MONARCH_LOCK_ONLY': str(lock_only).lower(),
         'LOCK_TEST_PGREP_HYPRLOCK': '1' if running else ''}
  env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
  if seq:
    seq_file = bin_dir / 'pgrep-seq'
    seq_file.write_text(seq + '\n')
    env['LOCK_TEST_PGREP_SEQ'] = str(seq_file)
  return subprocess.run(['/bin/bash', str(root / 'bin/monarch-system-lock')], env=env, capture_output=True, text=True)

for lock_only in (True, False):
  # hyprlock is the only lock: never Noctalia, whatever the session variables say.
  r = run(False, False, lock_only=lock_only)
  assert r.returncode == 127 and r.stderr.strip(), r
  assert 'noctalia' not in calls.read_text()
  r = run(True, True, lock_only=lock_only)
  assert r.returncode == 0 and not r.stderr, r
  assert 'setsid' not in calls.read_text(), 'an already running lock is not started twice'
  assert 'pkill -f [o]rg.monarch.screensaver' in calls.read_text()
  assert ('monarch-brightness-keyboard off' in calls.read_text()) == (not lock_only)
print('ok - a missing lock fails with a diagnostic, a running lock is not restarted, cleanup follows in both modes')

r = run(True, False)
assert r.returncode == 1 and 'hyprlock did not start' in r.stderr, r
# Starts, then dies at once: failure, not success.
r = run(True, False, '1 0 1')
assert r.returncode == 1 and 'exited at once' in r.stderr, r
assert 'setsid -f hyprlock' in calls.read_text()
# Starts and stays: success.
r = run(True, False, '1 0 0')
assert r.returncode == 0 and not r.stderr, r
# Never appears at all: failure.
r = run(True, False, '1 1')
assert r.returncode == 1, r
print('ok - hyprlock that never starts or dies at once is a failure, one that stays is success; Noctalia is never called')
PY
