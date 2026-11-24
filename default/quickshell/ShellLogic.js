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
