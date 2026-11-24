#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

QS="$ROOT/default/quickshell"
P="$QS/UsagePanel.qml"

[[ -f $P ]] || fail "UsagePanel.qml exists"
grep -q '^UsagePanel 1.0 UsagePanel.qml$' "$QS/qmldir" || fail "qmldir registers UsagePanel"
grep -q 'UsagePanel.qml' "$QS/PanelHost.qml" || fail "the host loads the usage panel"
grep -q 'first-steps, usage' "$ROOT/bin/monarch-panel" || fail "monarch-panel lists usage"
! grep -Eq '#[0-9a-fA-F]{6}' "$P" || fail "no color literals"
grep -q '"monarch-agent-usage-fetch"' "$P" || fail "the panel reads usage through the fetch helper"
# Read only: provider changes stay in the terminal manager.
! grep -Eq 'config (enable|disable|set)|set-api-key|enable --provider' "$P" || fail "the panel changes no provider setting"
grep -q 'function scrollBy' "$P" && grep -q 'contentHeight > windowsView.height' "$P" || fail "keyboard scroll and a scroll track exist"
grep -q 'Layout.rightMargin: 24' "$P" || fail "the header leaves room for the close button"

if ! command -v node >/dev/null 2>&1; then
  pass "skipped usage panel logic checks: node is not installed"
  exit 0
fi

out=$(QS="$QS" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.env.QS + "/ShellLogic.js", "utf8").replace(".pragma library", "");
const L = new Function(src + "; return {panelName, parseUsage, usageColor, providerName};")();
const out = [];
out.push(L.panelName("usage") === "usage");
const ok = JSON.stringify({ok: true, providers: [
  {provider: "codex", account: "a", usage: {identity: {plan: "Pro"}, primary: {usedPercent: 42.55, resetsAt: "2026-11-25T03:00:00Z"}, secondary: {usedPercent: 150}, tertiary: {usageKnown: false, usedPercent: 5}}},
  {provider: "synthetic", error: {message: "No key"}},
  {provider: "openrouter", usage: {providerCost: {used: 0, balance: 12.5, currencyCode: "USD"}}},
  {provider: "claude", stale: true},
  null]});
const r = L.parseUsage(ok);
out.push(r.providers.length === 4 && r.providers[0].name === "Codex" && r.providers[0].plan === "Pro");
out.push(r.providers[0].windows.length === 2 && r.providers[0].windows[1].used === 100 && r.providers[0].windows[0].reset === "2026-11-25 03:00 UTC");
out.push(r.providers[1].issue === "No key" && r.providers[1].empty === false);
out.push(r.providers[2].lines.length === 1 && r.providers[2].lines[0] === "Balance: 12.5 USD");
out.push(r.providers[3].stale === true && r.providers[3].empty === true);
// An unusable or failed-and-empty read is unavailable, never "no providers".
out.push(L.parseUsage("nope") === null && L.parseUsage("{}") === null && L.parseUsage("") === null);
out.push(L.parseUsage(JSON.stringify({ok: false, providers: []})) === null);
out.push(L.parseUsage(JSON.stringify({ok: true, providers: []})).providers.length === 0);
out.push(L.parseUsage(JSON.stringify({ok: false, providers: [{provider: "codex"}]})).ok === false);
out.push(L.usageColor(95) === "error" && L.usageColor(75) === "warn" && L.usageColor(10) === "ok");
console.log(out.map(Boolean).join(" "));
')
[[ $out == "true true true true true true true true true true true" ]] || fail "usage panel logic" "$out"
pass "usage parsing behaves"
