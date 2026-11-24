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
var PANELS = ["wifi-qr", "network", "theme"];

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
