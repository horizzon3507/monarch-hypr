.pragma library

// Pure settings logic for the Monarch shell. No Quickshell imports, so it runs
// in any QtQuick engine and in node (see test/shell.d/quickshell-core-test.sh).

var DEFAULTS = {
    barVisible: true,
    barPosition: "top",
    batteryPercent: false,
    textScale: 1.0
};

var POSITIONS = ["top", "bottom"];

function clamp(value, low, high) {
    return Math.min(high, Math.max(low, value));
}

// Returns a complete, valid settings object from untrusted JSON. Unknown keys
// are dropped and invalid values fall back to the default.
function normalize(input) {
    var src = (input && typeof input === "object") ? input : {};
    var out = {};
    out.barVisible = typeof src.barVisible === "boolean" ? src.barVisible : DEFAULTS.barVisible;
    out.barPosition = POSITIONS.indexOf(src.barPosition) >= 0 ? src.barPosition : DEFAULTS.barPosition;
    out.batteryPercent = typeof src.batteryPercent === "boolean" ? src.batteryPercent : DEFAULTS.batteryPercent;
    var scale = Number(src.textScale);
    out.textScale = isFinite(scale) && scale > 0 ? clamp(scale, 0.75, 2.0) : DEFAULTS.textScale;
    return out;
}

// Parses the settings file text. Empty or broken text gives the defaults.
function parse(text) {
    try {
        return normalize(JSON.parse(text));
    } catch (e) {
        return normalize(null);
    }
}

// Colors: accepts only #rrggbb values, falls back per key.
var COLOR_DEFAULTS = {
    bg: "#101014", fg: "#e6e6ea", accent: "#7aa2f7",
    outline: "#3b3b46", surfaceVariant: "#1c1c22", error: "#f7768e", secondary: "#bb9af7"
};

function colors(input) {
    var src = (input && typeof input === "object") ? input : {};
    var out = {};
    for (var key in COLOR_DEFAULTS) {
        var v = src[key];
        out[key] = (typeof v === "string" && /^#[0-9a-fA-F]{6}$/.test(v)) ? v.toLowerCase() : COLOR_DEFAULTS[key];
    }
    return out;
}

function parseColors(text) {
    try {
        return colors(JSON.parse(text));
    } catch (e) {
        return colors(null);
    }
}

// ---- Bar logic -------------------------------------------------------------

// Workspace ids the bar always shows, even when empty and not yet created.
var PERSISTENT_WORKSPACES = 5;

// Ids to draw: 1..5 always, plus any existing numbered workspace above that.
// Named (negative id) and special workspaces are left out.
function workspaceSlots(existingIds) {
    var seen = {};
    var ids = [];
    var i;
    for (i = 1; i <= PERSISTENT_WORKSPACES; i++) {
        seen[i] = true;
        ids.push(i);
    }
    var extra = (existingIds || []).filter(function (id) {
        return typeof id === "number" && isFinite(id) && id > PERSISTENT_WORKSPACES && Math.floor(id) === id;
    });
    extra.sort(function (a, b) { return a - b; });
    for (i = 0; i < extra.length; i++) {
        if (!seen[extra[i]]) {
            seen[extra[i]] = true;
            ids.push(extra[i]);
        }
    }
    return ids;
}

// Dispatcher string to focus a workspace, in the Lua form documented for the
// Hyprland session (unverified on a live compositor). Rejects non-integers.
function workspaceDispatch(id) {
    var n = Number(id);
    if (!isFinite(n) || Math.floor(n) !== n || n < 1) return "";
    return "hl.dsp.focus({ workspace = " + n + " })";
}

function pad2(n) {
    return (n < 10 ? "0" : "") + n;
}

var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function clockText(date) {
    if (!(date instanceof Date) || isNaN(date.getTime())) return "";
    return DAYS[date.getDay()] + " " + date.getDate() + " " + MONTHS[date.getMonth()]
        + "  " + pad2(date.getHours()) + ":" + pad2(date.getMinutes());
}

// Battery fraction (0..1, as UPowerDevice.percentage documents it as
// energy / energyCapacity) to whole percent, clamped.
function batteryPercent(fraction) {
    var f = Number(fraction);
    if (!isFinite(f)) return 0;
    return Math.round(clamp(f, 0, 1) * 100);
}

// Text for the battery indicator. `charging` is true while charging or full on AC.
function batteryText(fraction, charging, showPercent) {
    var pct = batteryPercent(fraction);
    var mark = charging ? "+" : "";
    return showPercent ? (mark + pct + "%") : (charging ? "charging" : (pct <= 15 ? "low" : ""));
}

// Volume fraction (1.0 = 100%) to whole percent, capped at 150.
function volumePercent(volume) {
    var v = Number(volume);
    if (!isFinite(v)) return 0;
    return Math.round(clamp(v, 0, 1.5) * 100);
}

function volumeText(volume, muted) {
    return muted ? "muted" : (volumePercent(volume) + "%");
}

// Signal strength (0.0 to 1.0 per WifiNetwork.signalStrength) to whole percent.
function signalPercent(strength) {
    var s = Number(strength);
    if (!isFinite(s)) return 0;
    return Math.round(clamp(s, 0, 1) * 100);
}

// Bluetooth readout. `connected` is the list of connected device names; an
// empty adapter state (null) hides the readout.
function bluetoothText(adapterEnabled, connected) {
    if (adapterEnabled === null || adapterEnabled === undefined) return "";
    if (!adapterEnabled) return "bt off";
    var names = (connected || []).filter(function (n) { return typeof n === "string" && n.length > 0; });
    if (names.length === 0) return "bt";
    if (names.length === 1) return "bt " + names[0];
    return "bt " + names.length;
}

// Panels the host knows. Names come from the IPC call, so anything else is
// refused rather than loaded.
var PANELS = ["wifi-qr", "network", "theme", "display", "background", "crashes", "first-steps", "usage"];

function panelName(name) {
    var n = String(name === undefined || name === null ? "" : name);
    return PANELS.indexOf(n) >= 0 ? n : "";
}

// New current panel after a toggle: the same name closes, another switches.
function togglePanel(current, name) {
    var next = panelName(name);
    if (next === "") return current;
    return current === next ? "" : next;
}

// Output of `monarch-wifi-qr --data`: one line
//   meta<TAB>interface<TAB>security<TAB>data:image/png;base64,...<TAB>ssid
// The image arrives in memory, so the credential-bearing QR never touches the
// disk. The SSID goes last because it is the only field that may contain a tab.
// Returns null when the line is not in that shape or the image is not a PNG data
// URI (a file path from a helper is refused, never opened).
function parseWifiQr(text) {
    var line = String(text === undefined || text === null ? "" : text).split("\n")[0];
    var m = /^meta\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$/.exec(line);
    if (!m || !/^data:image\/png;base64,[A-Za-z0-9+\/=]+$/.test(m[3])) return null;
    return { iface: m[1], security: m[2], image: m[3], ssid: m[4] };
}

// A WPA/WEP network has a password to reveal, an open one does not.
function wifiSecured(security) {
    return security !== "" && security !== "nopass";
}

// `monarch-wifi-panel list` prints one JSON object:
//   {"enabled":bool,"present":bool,"networks":[{key,ssid,security,signal,
//    connected,saved,uuid,device,connecting}, ...]}
// Returns null for anything else. Fields are re-typed so the panel never binds
// to a value of the wrong type; rows without a name are dropped.
function parseWifiSnapshot(text) {
    var data;
    try { data = JSON.parse(text); } catch (e) { return null; }
    if (!data || typeof data !== "object" || !Array.isArray(data.networks)) return null;
    // A snapshot with the wrong types is unknown, not evidence that the adapter
    // is missing or the radio is off: only real booleans count.
    if (typeof data.enabled !== "boolean" || typeof data.present !== "boolean") return null;
    var rows = [];
    for (var i = 0; i < data.networks.length; i++) {
        var n = data.networks[i];
        if (!n || typeof n.ssid !== "string" || n.ssid === "") continue;
        rows.push({
            key: String(n.key),
            ssid: n.ssid,
            security: typeof n.security === "string" ? n.security : "",
            signal: clamp(Number(n.signal) || 0, 0, 100),
            connected: n.connected === true,
            saved: n.saved === true,
            uuid: typeof n.uuid === "string" ? n.uuid : "",
            device: typeof n.device === "string" ? n.device : "",
            connecting: n.connecting === true
        });
    }
    return { enabled: data.enabled, present: data.present, networks: rows };
}

// What a click on a row does. A connected network disconnects. A saved or open
// network joins with what NetworkManager already has. An unsaved network that
// needs a password or credentials cannot be joined from this panel yet.
function wifiRowAction(net, stale) {
    if (!net || net.connecting || stale === true) return "";
    if (net.connected) return net.uuid !== "" && net.device !== "" ? "disconnect" : "";
    if (net.saved || net.security === "open") return "join";
    return "credentials";
}

// One-line status for the panel header.
function wifiHeader(snapshot) {
    if (snapshot === null) return "Wi-Fi status unavailable";
    if (!snapshot.present) return "No Wi-Fi adapter";
    if (!snapshot.enabled) return "Wi-Fi is off";
    for (var i = 0; i < snapshot.networks.length; i++)
        if (snapshot.networks[i].connected) return "Connected to " + snapshot.networks[i].ssid;
    return snapshot.networks.length > 0 ? "Not connected" : "No networks in range";
}

// The radio switch changes state from what the panel last read, so it needs a
// fresh, validated snapshot.
function wifiRadioEnabled(snapshot, stale) {
    return snapshot !== null && stale !== true;
}

// Output of `monarch-theme-list`: one theme per line,
//   selected<TAB>name<TAB>slug<TAB>preview path
// Lines that do not have those fields are dropped. null means nothing usable,
// which the panel shows as unavailable rather than as an empty list.
function parseThemeList(text) {
    var out = [];
    var lines = String(text === undefined || text === null ? "" : text).split("\n");
    for (var i = 0; i < lines.length; i++) {
        var f = lines[i].split("\t");
        if (f.length < 3 || f[1] === "" || (f[0] !== "true" && f[0] !== "false")) continue;
        out.push({ name: f[1], slug: f[2], selected: f[0] === "true" });
    }
    return out.length > 0 ? out : null;
}

// `monarch-theme-mode get` prints dark or light; anything else is unknown.
function parseThemeMode(text) {
    var m = String(text === undefined || text === null ? "" : text).trim();
    return m === "dark" || m === "light" ? m : "";
}

// Output of `monarch-display-list`: name, state (on/off), scale, mode, focused
// and description, tab separated. A disabled output has no scale or mode and is
// listed without controls. null means nothing usable (Hyprland not running).
function parseDisplayList(text) {
    var out = [];
    var lines = String(text === undefined || text === null ? "" : text).split("\n");
    for (var i = 0; i < lines.length; i++) {
        var f = lines[i].split("\t");
        if (f.length < 5 || f[0] === "" || (f[1] !== "on" && f[1] !== "off")) continue;
        var scale = Number(f[2]);
        out.push({
            name: f[0],
            enabled: f[1] === "on",
            scale: f[1] === "on" && isFinite(scale) && scale > 0 ? scale : 0,
            mode: f[3],
            focused: f[4] === "focused",
            description: f.length > 5 ? f.slice(5).join(" ") : ""
        });
    }
    return out.length > 0 ? out : null;
}

// Output of `monarch-display-brightness --list`: connector, percent, backend.
// Returns a map connector -> percent; outputs without a control are absent.
function parseBrightnessList(text) {
    var out = {};
    var lines = String(text === undefined || text === null ? "" : text).split("\n");
    for (var i = 0; i < lines.length; i++) {
        var f = lines[i].split("\t");
        if (f.length < 3 || f[0] === "" || !/^[0-9]+$/.test(f[1])) continue;
        var p = Number(f[1]);
        if (p > 100) continue;
        out[f[0]] = { percent: p, backend: f[2] };
    }
    return out;
}

// Scales the panel steps through. The next step from any value is the nearest
// listed step above or below it, so an odd current scale still moves.
var SCALE_STEPS = [0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3];

function stepScale(current, direction) {
    var c = Number(current);
    if (!isFinite(c) || c <= 0 || (direction !== 1 && direction !== -1)) return 0;
    var best = -1;
    if (direction === 1) {
        for (var i = 0; i < SCALE_STEPS.length; i++) if (SCALE_STEPS[i] > c + 0.001) { best = i; break; }
    } else {
        for (var j = SCALE_STEPS.length - 1; j >= 0; j--) if (SCALE_STEPS[j] < c - 0.001) { best = j; break; }
    }
    return best < 0 ? 0 : SCALE_STEPS[best];
}

// Brightness moves by 10 and stays within 5..100: the panel never steps a
// screen to fully dark.
function stepBrightness(percent, direction) {
    var p = Number(percent);
    if (!isFinite(p) || (direction !== 1 && direction !== -1)) return -1;
    return clamp(Math.round(p / 10) * 10 + direction * 10, 5, 100);
}

// `monarch-display-text-size --current` prints e.g. "115%". 0 when unknown.
function parseTextSize(text) {
    var m = /^\s*([0-9]+)%\s*$/.exec(String(text === undefined || text === null ? "" : text));
    return m ? Number(m[1]) : 0;
}

// Text size steps by 5 within the command's 75..175 range; 0 for an unknown start.
function stepTextSize(percent, direction) {
    var p = Number(percent);
    if (!isFinite(p) || p <= 0 || (direction !== 1 && direction !== -1)) return 0;
    return clamp(p + direction * 5, 75, 175);
}

// Bar readout for the internal backlight. null/absent hides it.
function brightnessText(map) {
    if (!map) return "";
    for (var k in map) if (map[k].backend === "backlight") return "bri " + map[k].percent + "%";
    return "";
}

// Output of `monarch-theme-background-list`: active, file name, path, thumbnail
// path and removable, tab separated. Only absolute paths are accepted. Blank
// output is a real empty list (a theme with no backgrounds). Non-blank output
// with no usable row is a different format or garbage, which is null (unusable)
// and must not read as "no backgrounds".
function parseBackgroundList(text) {
    var out = [];
    var raw = String(text === undefined || text === null ? "" : text);
    var lines = raw.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var f = lines[i].split("\t");
        if (f.length < 4 || (f[0] !== "true" && f[0] !== "false") || f[1] === "" || f[2].charAt(0) !== "/") continue;
        out.push({
            active: f[0] === "true",
            name: f[1],
            path: f[2],
            thumbnail: f[3].charAt(0) === "/" ? f[3] : ""
        });
    }
    if (out.length === 0 && raw.trim() !== "") return null;
    return out;
}

// Output of `monarch-crash-history list --json`:
//   {"crashes":[{id,application,date,signal,core,...}],"limit":N,"hasMore":bool}
// Entries without a well-formed id are dropped: the id goes back to the helper
// for a report, and the helper accepts only that shape. null means the output
// was not usable (a failed read), which differs from an empty list.
function parseCrashList(text) {
    var data;
    try { data = JSON.parse(text); } catch (e) { return null; }
    if (!data || typeof data !== "object" || !Array.isArray(data.crashes)) return null;
    var rows = [];
    for (var i = 0; i < data.crashes.length; i++) {
        var c = data.crashes[i];
        if (!c || typeof c.id !== "string" || !/^[a-f0-9]{32}:[0-9]{1,10}:[0-9]{1,20}$/.test(c.id)) continue;
        rows.push({
            id: c.id,
            application: typeof c.application === "string" && c.application !== "" ? c.application : "unknown",
            date: typeof c.date === "string" ? c.date : "",
            signal: typeof c.signal === "string" ? c.signal : "",
            core: typeof c.core === "string" ? c.core : ""
        });
    }
    return { crashes: rows, hasMore: data.hasMore === true };
}

// `monarch-crash-history export` prints {"path": "..."}; "" when unusable.
function parseExportPath(text) {
    try {
        var d = JSON.parse(text);
        return d && typeof d.path === "string" && d.path.charAt(0) === "/" ? d.path : "";
    } catch (e) { return ""; }
}

// ---- First steps -----------------------------------------------------------

var FIRST_STEPS = ["network", "update", "shortcuts", "appearance", "software"];

// The phase a guide opens at, from `monarch-setup-first-steps state`
// ({"shown":bool,"pending":bool,"phase":"..."}). Unknown phases start over.
function firstStepsPhase(text) {
    try {
        var d = JSON.parse(text);
        var p = d && typeof d.phase === "string" ? d.phase : "";
        return FIRST_STEPS.indexOf(p) >= 0 || p === "done" ? p : "welcome";
    } catch (e) { return "welcome"; }
}

// Phase after "next": welcome starts the steps, the last step ends at done.
function nextPhase(phase) {
    var i = FIRST_STEPS.indexOf(phase);
    if (i < 0) return phase === "welcome" ? FIRST_STEPS[0] : "";
    return i + 1 < FIRST_STEPS.length ? FIRST_STEPS[i + 1] : "done";
}

function prevPhase(phase) {
    var i = FIRST_STEPS.indexOf(phase);
    return i > 0 ? FIRST_STEPS[i - 1] : (i === 0 ? "welcome" : "");
}

// `monarch-setup-first-steps tools-state`. null when unusable, so the panel
// shows "state unavailable" instead of treating it as "nothing installed".
function parseToolsState(text) {
    var d;
    try { d = JSON.parse(text); } catch (e) { return null; }
    if (!d || typeof d !== "object" || !d.installed || typeof d.installed !== "object" || typeof d.connected !== "boolean") return null;
    return {
        installed: {
            burpsuite: d.installed.burpsuite === true,
            rfswift: d.installed.rfswift === true,
            seclists: d.installed.seclists === true
        },
        active: typeof d.active === "string" ? d.active : "",
        connected: d.connected,
        updateResult: d.updateResult && typeof d.updateResult.code === "number" ? d.updateResult : null,
        lastResult: d.lastResult && typeof d.lastResult.code === "number" && typeof d.lastResult.tool === "string" ? d.lastResult : null
    };
}

// `monarch-update-available --all --json` with its exit code: 0 available,
// 1 current, 2 error. Anything that does not fit is an error, never "current".
function parseUpdateCheck(text, exitCode) {
    var d;
    try { d = JSON.parse(text); } catch (e) { return { status: "error" }; }
    if (!d || typeof d !== "object" || typeof d.count !== "number") {
        if (d && exitCode === 2 && d.status === "error") return d;
        return { status: "error" };
    }
    if (exitCode === 1 && d.status === "current" && d.count === 0 && d.complete !== false) return d;
    if (exitCode === 0 && d.status === "available" && d.count > 0) return d;
    if (exitCode === 2 && d.status === "error") return d;
    return { status: "error" };
}

// What the update step shows and offers.
function updateView(check, tools, connected, toolsLoaded, checking) {
    var out = { title: "Checking for updates...", detail: "Reading the system repositories and the AUR.", canUpdate: false, button: "" };
    var result = tools ? tools.updateResult : null;
    var active = tools ? tools.active : "";
    var current = check && check.status === "current";
    var available = check && check.status === "available";
    var failedBefore = current && result !== null && result.code !== 0;
    var repair = check && check.status === "error" && check.reason === "repositories-unavailable";
    var partial = check && check.complete === false;
    if (active === "update") {
        out.title = "Update in progress..."; out.detail = "Follow it in the terminal.";
    } else if (active !== "") {
        out.title = "Installation in progress..."; out.detail = "The check starts when the installation ends.";
    } else if (toolsLoaded && !connected) {
        out.title = "Connection needed"; out.detail = "Connect to check for updates.";
    } else if (current) {
        out.title = failedBefore ? "Packages are current, finishing needs a retry" : "System is up to date";
        out.detail = failedBefore ? "The last attempt did not finish. Resume the configuration and post-update tasks." : "No update is available in the system repositories or the AUR.";
    } else if (available) {
        out.title = (partial ? "At least " : "") + check.count + (check.count === 1 ? " update available" : " updates available");
        out.detail = "System repositories: " + (check.repositories || 0) + " | AUR: " + (partial ? "not checked" : (check.aur || 0));
    } else if (check && check.status === "error") {
        out.title = "Could not check";
        out.detail = repair ? "The repository check failed. The terminal can offer to refresh the signing keys." : "The repositories could not be checked. Retry or continue later.";
    }
    out.canUpdate = (available || failedBefore || repair) && connected && active === "" && !checking;
    out.button = repair ? "Check in the terminal" : (failedBefore ? "Finish the update" : "Update now");
    out.failedBefore = failedBefore;
    out.current = current;
    return out;
}

// Label for a key binding chord, e.g. "SUPER ALT + Space" to "Win + Alt + Space".
function shortcutText(chord) {
    return String(chord === undefined || chord === null ? "" : chord)
        .replace(/SUPER/g, "Win").replace(/ALT/g, "Alt").replace(/Win Alt/g, "Win + Alt")
        .replace(/\s*\+\s*/g, " + ");
}

// The bindings the guide shows from `monarch-menu-keybindings --json`.
function firstStepsShortcuts(text) {
    var d;
    try { d = JSON.parse(text); } catch (e) { return []; }
    if (!Array.isArray(d)) return [];
    var out = [];
    for (var i = 0; i < d.length; i++) {
        var b = d[i];
        if (!b || typeof b.label !== "string" || typeof b.shortcut !== "string") continue;
        if (b.label !== "Terminal" && b.label !== "Monarch menu" && b.label.indexOf("Launcher") !== 0) continue;
        out.push({ label: b.label === "Monarch menu" ? "monarch-menu" : (b.label.indexOf("Launcher") === 0 ? "App launcher" : b.label), shortcut: shortcutText(b.shortcut) });
    }
    return out;
}

// ---- Agent usage -----------------------------------------------------------

var PROVIDER_NAMES = { codex: "Codex", claude: "Claude", synthetic: "Synthetic", openrouter: "OpenRouter" };

function providerName(p) {
    var id = String(p && (p.provider || p.id) || "unknown");
    return PROVIDER_NAMES[id] || (id.charAt(0).toUpperCase() + id.slice(1));
}

// `monarch-agent-usage-fetch` output: {"providers":[...],"ok":bool}. An
// unusable envelope, or a failed fetch with nothing in it, is null
// (unavailable), never "no providers".
function parseUsage(text) {
    var d;
    try { d = JSON.parse(text); } catch (e) { return null; }
    if (!d || typeof d !== "object" || !Array.isArray(d.providers) || typeof d.ok !== "boolean") return null;
    if (!d.ok && d.providers.length === 0) return null;
    var out = [];
    for (var i = 0; i < d.providers.length; i++) {
        if (d.providers[i] && typeof d.providers[i] === "object") out.push(usageProvider(d.providers[i]));
    }
    return { providers: out, ok: d.ok };
}

function usageIssue(p) {
    var e = p.error;
    if (e && typeof e === "object") return String(e.message || e.description || e.kind || "Provider unavailable");
    return e ? String(e) : "";
}

function usageReset(t) {
    return String(t).replace(/^(\d{4}-\d\d-\d\d)T(\d\d:\d\d):\d\dZ$/, "$1 $2 UTC");
}

function usageWindows(p) {
    var usage = p.usage || {}, labels = p.rateWindowLabels || {}, rows = [], seen = [];
    function add(key, w, label) {
        if (!w || typeof w !== "object" || w.usageKnown === false || seen.indexOf(w) >= 0 || isNaN(parseFloat(w.usedPercent))) return;
        seen.push(w);
        rows.push({
            title: String(label || labels[key] || w.title || w.label || key),
            used: Math.max(0, Math.min(100, parseFloat(w.usedPercent))),
            reset: w.resetsAt ? usageReset(w.resetsAt) : ""
        });
    }
    ["primary", "secondary", "tertiary"].forEach(function (k) { add(k, usage[k]); });
    (usage.extraRateWindows || []).forEach(function (x) { if (x && x.usageKnown !== false) add("Additional quota", x.window || x, x.title || x.name); });
    (usage.windows || []).forEach(function (x) { if (x) add("Quota", x.window || x, x.title || x.name); });
    return rows;
}

function usageProvider(p) {
    var usage = p.usage || {}, identity = usage.identity || {}, cost = usage.providerCost;
    var credits = p.credits || usage.credits;
    var lines = [];
    if (cost && typeof cost === "object") {
        var used = parseFloat(cost.used), limit = parseFloat(cost.limit);
        var hideSpend = cost.balance !== undefined && cost.balance !== null && used === 0 && (isNaN(limit) || limit === 0);
        if (!isNaN(used) && !hideSpend) {
            lines.push("Spend: " + used + (limit > 0 ? " of " + limit : "") + (cost.currencyCode ? " " + cost.currencyCode : "") + (cost.period ? " (" + cost.period + ")" : ""));
        }
        if (cost.balance !== undefined && cost.balance !== null) lines.push("Balance: " + cost.balance + (cost.currencyCode ? " " + cost.currencyCode : ""));
    }
    if (credits && typeof credits === "object" && credits.remaining !== undefined && credits.remaining !== null) lines.push("Credits: " + credits.remaining);
    var windows = usageWindows(p), issue = usageIssue(p);
    return {
        key: String(p.provider || p.id || "unknown") + ":" + String(p.account || ""),
        name: providerName(p),
        plan: String(identity.plan || identity.accountEmail || p.source || ""),
        issue: issue,
        windows: windows,
        lines: lines,
        stale: p.stale === true,
        empty: windows.length === 0 && issue === "" && lines.length === 0
    };
}

function usageColor(used) { return used >= 90 ? "error" : (used >= 70 ? "warn" : "ok"); }
