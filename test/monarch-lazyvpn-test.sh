#!/bin/bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$root" <<'PY'
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

repo = Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='lazyvpn-integration-') as temporary:
    tmp = Path(temporary)
    root, home, bins = tmp / 'runtime', tmp / 'home', tmp / 'bin'
    bins.mkdir()
    home.mkdir()
    files = ['bin/monarch-install-lazyvpn', 'bin/monarch-remove-lazyvpn',
             'install/helpers/lazyvpn.sh', 'install/reconcile/lazyvpn.sh']
    for relative in files:
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        text = (repo / relative).read_text()
        # Redirect trusted package paths only in the disposable test runtime.
        text = text.replace('/usr/bin/monarch-lazyvpn', str(bins / 'monarch-lazyvpn'))
        text = text.replace('/usr/share/monarch-lazyvpn', str(tmp / 'assets'))
        text = text.replace('/usr/share/applications/monarch-lazyvpn.desktop', str(tmp / 'app.desktop'))
        target.write_text(text)
        target.chmod(0o755 if relative.startswith('bin/') else 0o644)

    def stub(name, text):
        target = bins / name
        target.write_text('#!/bin/bash\n' + text)
        target.chmod(0o755)

    stub('monarch-lazyvpn', '''
if [[ $* == "--preview --help" ]]; then exit "${OLD_BACKEND:-0}"; fi
echo gui >>"$HOME/launch.log"
exit "${GUI_FAILURE:-0}"
''')
    stub('pacman', '''
[[ $* == "-Q monarch-lazyvpn" ]] || exit 2
[[ ${MISSING:-0} == 0 ]] || exit 1
echo "monarch-lazyvpn ${VERSION:-0.2.0-1}"
''')
    stub('monarch-pkg-add', 'exit "${PKG_FAILURE:-0}"\n')
    stub('vercmp', '''
[[ $2 == "0.2.0" ]] || exit 2
[[ ${VERCMP_FAILURE:-0} == 0 ]] || exit 3
case $1 in
  0.1.5-1 | 0.2.0rc1-1) echo -1 ;;
  0.2.0) echo 0 ;;
  0.2.0-1 | 0.2.0-12 | 0.10.0-1 | 1:0.2.0-1) echo 1 ;;
  *) exit 2 ;;
esac
''')
    stub('monarch-pkg-drop', 'exit "${PKG_FAILURE:-0}"\n')
    stub('pgrep', 'exit 1\n')
    stub('monarch-cmd-present', 'exit 1\n')
    stub('terminal', 'echo terminal >>"$HOME/launch.log"\n')
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / 'config'),
               XDG_DATA_HOME=str(home / 'data'), PATH=f'{bins}:{root}/bin:' + os.environ['PATH'])
    config, data = Path(env['XDG_CONFIG_HOME']), Path(env['XDG_DATA_HOME'])
    legacy = data / 'applications/LazyVPN.desktop'
    legacy.parent.mkdir(parents=True)
    legacy.write_text('Exec=monarch-launch-floating-terminal-with-presentation monarch-lazyvpn\n')
    (config / 'monarch-lazyvpn').mkdir(parents=True)
    profile = config / 'monarch-lazyvpn/profile.conf'
    profile.write_text('preserve me')

    def run(script, success=True, **overrides):
        result = subprocess.run(['bash', '-euo', 'pipefail', '-c', script],
                                env=dict(env, **overrides), capture_output=True, text=True)
        assert (result.returncode == 0) == success, result.stdout + result.stderr
        return result

    reconcile = f'source "{root}/install/reconcile/lazyvpn.sh"; monarch_reconcile_lazyvpn "{root}"'
    for overrides in ({'MISSING': '1'}, {'VERSION': '0.1.5-1'}, {'VERSION': '0.2.0rc1-1'}, {'OLD_BACKEND': '1'}):
        run(reconcile, **overrides)
        assert legacy.exists()
    run(reconcile, success=False)
    run(reconcile, success=False, VERCMP_FAILURE='1')
    assert legacy.exists()
    print('ok - absent/old/incomplete packages leave the legacy launcher alone')

    (tmp / 'app.desktop').write_text('[Desktop Entry]\nExec=monarch-lazyvpn\n')
    run(reconcile)
    run(reconcile)
    assert not legacy.exists() and legacy.with_suffix('.desktop.pre-gpui').exists()
    assert not (home / '.config/niri').exists() and not (config / 'noctalia').exists()
    assert profile.read_text() == 'preserve me'
    print('ok - reconciliation is idempotent, removes the legacy launcher and preserves profiles')

    for version in ('0.2.0', '0.2.0-12', '0.10.0-1', '1:0.2.0-1'):
        run(reconcile, VERSION=version)
    installer = f'"{root}/bin/monarch-install-lazyvpn"'
    run(installer)
    run(installer, success=False, PKG_FAILURE='9')
    run(installer, success=False, OLD_BACKEND='1')
    print('ok - fresh installation and package/backend failure paths')

    remove = f'"{root}/bin/monarch-remove-lazyvpn"'
    run(remove, success=False, PKG_FAILURE='9')
    run(remove)
    assert not legacy.exists()
    assert profile.read_text() == 'preserve me'
    print('ok - removal fails on pacman failure and always preserves profile data')
PY
