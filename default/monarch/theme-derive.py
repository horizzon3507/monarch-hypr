#!/usr/bin/env python3
"""Derive the extra color roles editor themes need from a Monarch palette.

Monarch palettes carry 16 roles plus a terminal block. Editor themes (Zed,
VS Code) want more surfaces and container pairs than that. This fills them in
by blending colors the palette already has, so the result follows the palette
and needs no extra data. Pure stdlib, deterministic, original work.

Usage: theme-derive.py <palette.json> [dark|light]
Prints one JSON object per variant present, or only the one asked for:
  {"dark": {"surface_container": "#rrggbb", ...}, "light": {...}}
Every value is a six-digit lowercase hex color. Exit 1 on an invalid palette.
"""
import json
import re
import sys

HEX = re.compile(r"^#[0-9a-fA-F]{6}$")
REQUIRED = {
    "surface": "mSurface", "on_surface": "mOnSurface", "surface_variant": "mSurfaceVariant",
    "on_surface_variant": "mOnSurfaceVariant", "outline": "mOutline",
    "primary": "mPrimary", "on_primary": "mOnPrimary", "secondary": "mSecondary",
    "on_secondary": "mOnSecondary", "tertiary": "mTertiary", "on_tertiary": "mOnTertiary",
    "error": "mError", "on_error": "mOnError",
}
MIN_CONTRAST = 4.5


def parse(value):
    return tuple(int(value[i:i + 2], 16) for i in (1, 3, 5))


def fmt(rgb):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(c))) for c in rgb)


def mix(a, b, amount):
    """amount of b blended into a, both hex strings."""
    pa, pb = parse(a), parse(b)
    return fmt(tuple(x + (y - x) * amount for x, y in zip(pa, pb)))


def luminance(value):
    def channel(c):
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(c) for c in parse(value))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def readable_on(fg, bg, minimum=MIN_CONTRAST):
    """fg nudged toward white or black, whichever reaches the ratio, until it reads on bg."""
    if contrast(fg, bg) >= minimum:
        return fg
    # Whichever extreme reads better on this background; mid tones can favor black.
    target = "#ffffff" if contrast("#ffffff", bg) >= contrast("#000000", bg) else "#000000"
    for step in range(1, 21):
        candidate = mix(fg, target, step / 20)
        if contrast(candidate, bg) >= minimum:
            return candidate
    return target


def derive_variant(block, name):
    roles = {}
    for role, key in REQUIRED.items():
        value = block.get(key)
        if not isinstance(value, str) or not HEX.match(value):
            raise ValueError("%s: missing or invalid %s" % (name, key))
        roles[role] = value.lower()
    s, on = roles["surface"], roles["on_surface"]
    dark = luminance(s) < 0.4
    roles["background"] = s
    roles["on_background"] = on
    # Surfaces step from the base toward the text color; dim goes the other way.
    roles["surface_dim"] = mix(s, "#000000" if dark else "#ffffff", 0.2 if dark else 0.1)
    roles["surface_container_low"] = mix(s, on, 0.04)
    roles["surface_container"] = mix(s, on, 0.08)
    roles["surface_container_high"] = mix(s, on, 0.12)
    roles["surface_container_highest"] = mix(s, on, 0.16)
    roles["outline_variant"] = mix(roles["outline"], s, 0.5)
    for accent in ("primary", "secondary", "tertiary", "error"):
        container = mix(s, roles[accent], 0.3 if dark else 0.22)
        roles[accent + "_container"] = container
        roles["on_" + accent + "_container"] = readable_on(roles[accent], container)
        roles["on_" + accent] = readable_on(roles["on_" + accent], roles[accent])
    # Fixed accents keep their look in both modes: the accent itself and a dimmer step.
    for accent in ("primary", "secondary", "tertiary"):
        roles[accent + "_fixed"] = mix(roles[accent], "#ffffff", 0.7)
        roles[accent + "_fixed_dim"] = mix(roles[accent], "#ffffff", 0.45)
        roles["on_" + accent + "_fixed"] = readable_on(mix(roles[accent], "#000000", 0.8), roles[accent + "_fixed"])
        roles["on_" + accent + "_fixed_variant"] = readable_on(mix(roles[accent], "#000000", 0.6), roles[accent + "_fixed"])
    return roles


def derive(palette, only=None):
    out = {}
    for variant in ("dark", "light"):
        if only and variant != only:
            continue
        if variant in palette:
            out[variant] = derive_variant(palette[variant], variant)
    if not out:
        raise ValueError("no %s variant in the palette" % (only or "dark or light"))
    return out


def main(argv):
    if len(argv) not in (2, 3) or (len(argv) == 3 and argv[2] not in ("dark", "light")):
        print("Usage: theme-derive.py <palette.json> [dark|light]", file=sys.stderr)
        return 2
    try:
        with open(argv[1]) as handle:
            palette = json.load(handle)
        result = derive(palette, argv[2] if len(argv) == 3 else None)
    except (OSError, ValueError) as error:
        print("theme-derive: %s" % error, file=sys.stderr)
        return 1
    json.dump(result, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
