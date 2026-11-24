#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

python3 -B - "$ROOT" <<'PY' || fail "menu panel rows"
import json, re, sys
root = sys.argv[1]
text = open(root + "/default/monarch/monarch-menu.jsonc").read()
text = "\n".join(l for l in text.split("\n") if not l.strip().startswith("//"))
text = re.sub(r",(\s*[}\]])", r"\1", text)
menu = json.loads(text)
rows = {
    "setup.network.panel": ("network", "monarch-launch-wifi"),
    "style.theme-panel": ("theme", "monarch-menu-theme"),
    "style.background-panel": ("background", "monarch-menu-background"),
    "trigger.hardware.display-panel": ("display", "monarch-menu-display"),
    "system.crash-panel": ("crashes", "monarch-crash-history"),
    "system.usage-panel": ("usage", "monarch-agent-usage manage"),
}
panels = re.search(r"var PANELS = \[([^\]]*)\]", open(root + "/default/quickshell/ShellLogic.js").read()).group(1)
for rid, (panel, fallback) in rows.items():
    row = menu[rid]
    assert row["action"].startswith("monarch-panel open %s || " % panel), rid
    assert fallback in row["action"], rid + " keeps a terminal fallback"
    assert "monarch-panel active" in row["when"], rid + " is hidden while the shell is down"
    assert '"%s"' % panel in panels, rid + " names a real panel"
    parent = rid.rsplit(".", 1)[0]
    assert parent in menu, rid + " has a parent menu"
    for lang in ("en", "fr"):
        labels = json.load(open(root + "/default/i18n/%s.json" % lang))["menu"]
        assert labels.get(rid + ".label"), "%s has a %s label" % (rid, lang)
# The terminal routes stay: nothing was replaced.
assert menu["trigger.share.wifi"]["action"].endswith("monarch-wifi-qr")
assert menu["setup.network.wifi"]["action"] == "monarch-launch-wifi"
assert menu["style.theme"]["action"] == "monarch-menu-theme"
assert menu["system.crashes"]["action"] == "monarch-crash-history"
PY
pass "panel menu rows keep a terminal fallback and the terminal rows stay"
