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
