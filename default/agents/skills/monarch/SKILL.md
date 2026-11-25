---
name: monarch
description: >
  Use for end-user customization of the Linux desktop, window manager, or system config.
  Applies when editing ~/.config/hypr/, ~/.config/monarch/, ~/.config/alacritty/,
  ~/.config/foot/, ~/.config/kitty/ or ~/.config/ghostty/.
  Topics: Hyprland, window rules, animations, keybindings, monitors, gaps, borders,
  opacity, the Quickshell bar and panels, Walker launcher, notifications, lock screen,
  OSD, terminal config, themes, wallpaper, night light, idle, screenshots, reminders,
  workspace settings, display config, and user-facing monarch commands. Excludes Monarch
  source development and `monarch dev` workflows.
---

# Monarch Skill

Manage [Monarch](https://www.monarchlinux.com/) Linux systems, an opinionated Arch Linux distribution built on Hyprland and a thin Quickshell desktop shell.

This skill is for end-user customization on installed systems.
It is not for contributing to Monarch source code.

## When To Use This Skill

Use it for end-user requests that involve any of these:

- Editing files in `~/.config/hypr/` (window rules, keybindings, monitors, look and feel)
- Editing files in `~/.config/monarch/` (palettes, shell settings, hooks)
- Editing terminal configs (alacritty, foot, kitty, ghostty)
- Window behavior, opacity, gaps, borders
- Workspace settings, display and monitor configuration
- Color schemes, dark/light mode, wallpapers, fonts, appearance changes
- User-facing `monarch` commands (`monarch refresh ...`, `monarch restart ...`, etc.)
- Screenshots, screen recording, reminders, night light, idle behavior, lock screen

Before editing a config file in `~/.config/` on this system, check this skill first.

Do not use it for Monarch source development or `monarch dev ...` workflows.

## Critical Safety Rules

**For end-user customization tasks, never modify anything in `/usr/share/monarch/`.** Reading it is safe and encouraged.

This directory contains Monarch files managed by pacman. Any changes will be:
- Lost on next `monarch update`
- Invisible to user-owned configuration
- Liable to break the installed package

```
/usr/share/monarch/         # Packaged defaults, READ-ONLY
├── bin/                    # Source scripts (symlinked to PATH)
├── config/                 # Default user config templates (hypr, mako, walker, palettes, ...)
├── themes/                 # Per-theme wallpapers (themes/<theme>/*.png|jpg)
├── default/                # System defaults (hypr/, quickshell/, monarch/ theme templates)
└── install/                # Installation scripts
```

Read `/usr/share/monarch/` freely to:
- Understand how monarch commands work: `monarch refresh --help` or `cat $(which monarch-refresh-hypr)`
- See default Hyprland modules before customizing: `ls /usr/share/monarch/default/hypr/` and `cat /usr/share/monarch/default/hypr/rules.lua`
- See the shipped user config templates: `ls /usr/share/monarch/config/hypr/`
- Inspect a shipped palette: `cat /usr/share/monarch/config/monarch/palettes/Monarch.json`

Edit only these locations:
- `~/.config/hypr/` - Hyprland user files (safe to edit)
- `~/.config/monarch/` - palettes, shell settings, hooks (safe to edit)
- `~/.config/<app>/` - app configs

If the request is to develop Monarch itself, this skill is out of scope. Follow repository development instructions instead.

## System Architecture

Monarch is built on:

| Component | Purpose | Config Location |
|-----------|---------|-----------------|
| **Arch Linux** | Base OS | `/etc/`, `~/.config/` |
| **Hyprland** | Wayland compositor/WM, configured in Lua | `~/.config/hypr/` |
| **Quickshell shell** | Thin custom shell: bar, workspaces, tray, status chips and panels (Wi-Fi QR, network, theme, display, background, crash reports, first steps, usage) | `~/.config/monarch/shell.json` |
| **Walker** | Launcher, clipboard, emoji picker, Monarch menus | `~/.config/walker/` |
| **Mako** | Notifications and do-not-disturb | `~/.config/mako/config` |
| **Hyprlock / Hypridle** | Lock screen and idle handling | `~/.config/hypr/hyprlock.conf`, `hypridle.conf` |
| **Quickshell shell** | Wallpaper (use `monarch wallpaper`) | `~/.config/monarch/current/wallpaper.json` |
| **SwayOSD** | Volume and brightness on-screen display | `~/.config/swayosd/` |
| **Alacritty/Foot/Kitty/Ghostty** | Terminals | `~/.config/<terminal>/` |

The shell is deliberately small. There is no separate audio or Bluetooth panel: audio, Bluetooth and Wi-Fi settings open in terminal tools (`monarch launch audio` uses `wiremix`, `monarch launch bluetooth` uses `bluetui`, `monarch launch wifi` uses `impala`). Panels can be opened from a shell with `monarch panel toggle <panel>`.

## Command Discovery

Monarch ships a single `monarch` CLI that dispatches to all `monarch-*` binaries via `monarch <group> <action>`. Always prefer this form — it is self-documenting and stable. The underlying `monarch-*` binaries still exist on `PATH` and remain safe to read for source.

```bash
# List every documented command and its summary
monarch commands

# Show the commands inside a group
monarch refresh --help
monarch restart --help
monarch theme --help

# Show help for a specific command (does not execute it)
monarch theme apply --help

# Machine-readable listing (binary, route, summary, args, aliases)
monarch commands --json

# Read a command's source to understand it
cat $(which monarch-refresh-hypr)
```

### Command Groups

Run `monarch --help` for the full list. The most common groups:

| Group | Purpose | Example |
|-------|---------|---------|
| `monarch refresh` | Reset config to defaults (backs up first) | `monarch refresh shell` |
| `monarch restart` | Restart a service/app | `monarch restart shell` |
| `monarch toggle` | Toggle feature on/off | `monarch toggle nightlight` |
| `monarch theme` | Set, list and render themes and dark/light mode | `monarch theme set Lumon` |
| `monarch panel` | Open or close a shell panel | `monarch panel toggle theme` |
| `monarch install` | Install optional software / packages | `monarch install docker dbs` |
| `monarch launch` | Launch apps | `monarch launch browser` |
| `monarch capture` | Screenshots and recordings | `monarch capture screenshot` |
| `monarch reminder` | Desktop notification reminders | `monarch reminder 15 "Pickup Jack"` |
| `monarch pkg` | Package management | `monarch pkg install <pkg>` |
| `monarch setup` | Initial setup tasks | `monarch setup fingerprint` |
| `monarch update` | System updates | `monarch update` |

## Configuration Locations

### Hyprland (Window Manager)

```
~/.config/hypr/
├── hyprland.lua   # Entry point, generated by monarch-refresh-hypr. Do not edit.
├── monitors.lua   # Your monitor setup
├── input.lua      # Your input settings
├── bindings.lua   # Your key bindings
├── looknfeel.lua  # Your gaps, borders, rounding, animations
├── autostart.lua  # Your startup commands
└── keyboard.lua   # Generated keyboard layout
```

Monarch's own defaults live in `/usr/share/monarch/default/hypr/` and load first. The user files above load last, so they win.

**Key behaviors:**
- Hyprland reloads its config when a loaded file changes. To force a reload: `hyprctl reload`.
- To reinstall the entry point and seed any missing user file (never overwriting edits): `monarch refresh hypr`.
- Window rules, workspace rules and layer rules are Lua calls: `hl.window_rule({ match = {...}, ... })`. A user file can add its own after the defaults. Check the Hyprland wiki (<https://wiki.hypr.land/configuring/>) for the fields before writing one, and read `/usr/share/monarch/default/hypr/rules.lua` for working examples.
- Edit the user files in `~/.config/hypr/`, never the packaged `default/hypr/` modules.

### Shell (Quickshell)

The shell reads one settings file, `~/.config/monarch/shell.json`, and reloads when it changes. Read or write it with `monarch-shell-setting`:

```bash
monarch-shell-setting get barPosition          # "top" or "bottom"
monarch-shell-setting set barPosition '"bottom"'
monarch-shell-setting set barVisible false
monarch-shell-setting set batteryPercent true
monarch-shell-setting set textScale 1.2
```

Values are JSON. Other keys are ignored. `monarch toggle bar` flips bar visibility. `monarch restart shell` restarts bar, notifications, OSD, idle and wallpaper. `monarch refresh shell` resets mako, walker, swayosd, hyprlock, hypridle and the Monarch palette to defaults, re-renders the theme and restarts the shell, so ask before running it.

Custom bar widgets and plugin systems do not exist. The bar shows workspaces, the tray, connectivity, brightness, volume, battery, a clock and status chips (recording, caffeine, do not disturb, night light, update available). If the user wants a layout the settings file cannot express, say so rather than editing files under `/usr/share/monarch/default/quickshell/`.

### Terminals

```
~/.config/alacritty/alacritty.toml
~/.config/foot/foot.ini
~/.config/kitty/kitty.conf
~/.config/ghostty/config
```

**Command:** `monarch restart terminal`

### Other Configs

| App | Location |
|-----|----------|
| btop | `~/.config/btop/btop.conf` |
| fastfetch | `/etc/fastfetch/config.jsonc` default; `~/.config/fastfetch/config.jsonc` user override |
| lazygit | `~/.config/lazygit/config.yml` |
| starship | `~/.config/starship.toml` |
| git | `~/.config/git/config` |
| mako | `~/.config/mako/config` |
| walker | `~/.config/walker/config.toml` |

## Safe Customization Patterns

### Pattern 1: Edit User Config Directly

For simple changes, edit files in `~/.config/`:

```bash
# 1. Read the current file
cat ~/.config/hypr/bindings.lua

# 2. Back up before changes
cp ~/.config/hypr/bindings.lua ~/.config/hypr/bindings.lua.bak.$(date +%s)

# 3. Make changes with the Edit tool

# 4. Apply changes
# - Hyprland:  hyprctl reload   (a Lua error shows as a notification and in `hyprctl configerrors`)
# - Shell:     monarch restart shell
# - Terminals: monarch restart terminal
```

### Pattern 2: Change the theme

Themes are palette files: `~/.config/monarch/palettes/<Name>.json`, each with `dark` and `light` blocks. Monarch renders the active palette into the config templates for Hyprland, Mako, Walker, Hyprlock, SwayOSD and the terminals.

- List themes: `monarch theme list`. Show the active one: `monarch theme current`.
- Switch: `monarch theme set <Name>` (for example `monarch theme set Lumon`). The name must match a palette file, and a failed render leaves the previous theme active.
- Dark/light: `monarch theme mode toggle` (or `dark`, `light`, `get`).
- The theme panel (`monarch panel toggle theme`) is the visual picker.
- Tweak a palette: edit `~/.config/monarch/palettes/<Name>.json`, then `monarch theme render` (or `monarch theme set <Name>` again).
- Wallpapers belong to the active theme. Import your own with `monarch theme background-import [path]` (without a path it opens the file chooser). Set one directly with `monarch wallpaper set <path>`. Shipped backgrounds are never modified.
- `monarch theme apply` re-syncs the residual system layer (keyboard RGB, Chromium policy color) after a change.

Theming of other apps (Helix, Obsidian, editors) is done by their own `monarch` commands where they exist; do not assume they follow the theme automatically.

### Pattern 3: Use Hooks for Automation

Create scripts in `~/.config/monarch/hooks/` to run automatically on events:

```bash
# Available hooks (see samples in ~/.config/monarch/hooks/):
~/.config/monarch/hooks/
├── font-set         # Runs after font change
└── post-update      # Runs after `monarch update`
```

Example hook (`~/.config/monarch/hooks/font-set`):
```bash
#!/bin/bash
FONT_NAME=$1
echo "Font changed to: $FONT_NAME"
# Add custom actions here
```

### Pattern 4: Reset to Defaults (ask the user first)

When customizations go wrong, and only after the user agrees:

```bash
# Reset one config file (creates a backup automatically)
monarch refresh config <path relative to ~/.config>
monarch refresh hypr      # reinstall the entry point, seed missing user files
monarch refresh shell     # shell-related configs, theme, restart
```

Refresh commands back up the current file with a timestamp before replacing it.

## Common Tasks

### Themes

```bash
monarch theme list
monarch theme set <Name>
monarch theme mode toggle
monarch panel toggle theme
```

### Keybindings

Edit `~/.config/hypr/bindings.lua`. Monarch provides helpers for binds:

```lua
-- Run a command
monarch.cmd("SUPER + SHIFT + A", "monarch-launch-webapp https://chatgpt.com", "ChatGPT")
monarch.cmd("SUPER + E", "nautilus", "Files")

-- Any Hyprland dispatcher
monarch.bind("SUPER + Q", hl.dsp.window.close(), "Close window")
```

View current bindings: `monarch menu keybindings` (Super+K opens the same list). The Hyprland binds wiki is the reference for dispatchers and flags: <https://wiki.hypr.land/configuring/>. Defaults are in `/usr/share/monarch/default/hypr/binds/` and `shell.lua`. Check for an existing chord there before adding a bind, and tell the user if the new one overlaps a default.

### Display/Monitors

Edit `~/.config/hypr/monitors.lua`:

```lua
hl.monitor({ output = "eDP-1", mode = "2880x1920@120", position = "0x0", scale = 2 })
hl.monitor({ output = "DP-1", mode = "3840x2160@60", position = "1440x0", scale = 1.5 })
```

List outputs and modes: `hyprctl monitors`. The display panel (`monarch panel toggle display`) changes scale and mode interactively.

### Window Rules

Add rules to a user file such as `~/.config/hypr/looknfeel.lua`:

```lua
hl.window_rule({
  match = { class = "^org\\.telegram\\.desktop$" },
  float = true,
  size = "600 800",
})
```

Read `/usr/share/monarch/default/hypr/rules.lua` and the Hyprland window-rules page (<https://wiki.hypr.land/configuring/core/rules/window-rules/>) for the full field list before writing rules. Reload with `hyprctl reload`, and check `hyprctl configerrors`.

### Wallpaper, night light, do not disturb, idle

```bash
monarch wallpaper get
monarch wallpaper set ~/Pictures/wall.png
monarch toggle nightlight        # hyprsunset, manual on/off
monarch toggle notification-silencing   # mako do-not-disturb mode
monarch toggle idle              # hold the idle inhibitor (caffeine)
```

Night light is a manual toggle. There is no sunset schedule setting. If a status check reports the state as unavailable, say so instead of assuming off.

### Optional desktop hooks that are not available on Hyprland

Todo and LazyVPN install as packages and their commands still work in a terminal, but they have no keybinding, bar item or panel on Hyprland. Do not promise them. Add a keybinding in `bindings.lua` if the user asks.

### Fonts

```bash
monarch font list               # Available fonts
monarch font current            # Current font
monarch font set <name>         # Change font
```

### System

```bash
monarch update                  # Full system update
monarch version                 # Show Monarch version
monarch debug --no-sudo --print # Debug info (ALWAYS use these flags)
monarch system lock             # Lock screen
monarch system shutdown         # Shutdown
monarch system reboot           # Reboot
```

**IMPORTANT:** Always run `monarch debug` with `--no-sudo --print` flags to avoid interactive sudo prompts that will hang the terminal.

## Troubleshooting

```bash
# Get debug information (ALWAYS use these flags to avoid interactive prompts)
monarch debug --no-sudo --print

# Upload logs for support
monarch upload log

# Reset specific config to defaults
monarch refresh <app>

# Refresh specific config file
# config-file path is relative to ~/.config/
# eg. `monarch refresh config mako/config` will refresh ~/.config/mako/config
monarch refresh config <config-file>

# Full reinstall of configs (nuclear option)
monarch reinstall
```

## Decision Framework

When user requests system changes:

1. **Is it a stock monarch command?** Use it directly via `monarch <group> <action>`
2. **Is it a config edit?** Edit in `~/.config/`, never `/usr/share/monarch/`
3. **Is it a theme / color change?** Use `monarch theme set`, `monarch theme mode`, or edit a palette in `~/.config/monarch/palettes/`
4. **Is it automation?** Use hooks in `~/.config/monarch/hooks/`
5. **Is it a package install?** Use `monarch pkg add` (or `monarch pkg aur add` for AUR-only packages)
6. **Unsure if command exists?** Run `monarch commands` or `monarch <group> --help`

### Reminder Requests

When the user asks to set a reminder, use `monarch reminder <minutes> [message]` directly. Convert natural language durations to minutes and title-case short reminder labels when appropriate.

```bash
monarch reminder 15 "Pickup Jack"
monarch reminder 60 "Check laundry"
monarch reminder show
monarch reminder clear
```

## Out of Scope

This skill intentionally does not cover Monarch source development. Do not use this skill for:
- Editing packaged files in `/usr/share/monarch/`
- Running `monarch dev ...` commands

## Example Requests

- "Change my theme to catppuccin" -> `monarch theme set Catppuccin`
- "Switch to light mode" -> `monarch theme mode light`
- "Add a keybinding for Super+E to open file manager" -> Add `monarch.cmd("SUPER + E", "nautilus", "Files")` to `~/.config/hypr/bindings.lua`, then `hyprctl reload`
- "Configure my external monitor" -> Edit `~/.config/hypr/monitors.lua`, or use the display panel
- "Make the window gaps smaller" -> Set the gaps in `hl.config({ general = { gaps_in = ..., gaps_out = ... } })` in `~/.config/hypr/looknfeel.lua`, then `hyprctl reload`
- "Turn on night light" -> `monarch toggle nightlight` (manual only, no sunset schedule)
- "Set a reminder to pickup jack in 15 minutes" -> `monarch reminder 15 "Pickup Jack"`
- "Show my reminders" -> `monarch reminder show`
- "Clear all reminders" -> `monarch reminder clear`
- "Customize the Monarch palette" -> Edit `~/.config/monarch/palettes/Monarch.json` (`dark`/`light` blocks), then `monarch theme render`
- "Re-apply theming to keyboard RGB or Chromium" -> `monarch theme apply`
- "Move the bar to the bottom" -> `monarch-shell-setting set barPosition '"bottom"'`
- "Hide the bar" -> `monarch toggle bar`
- "Reset the shell to defaults" -> Ask first, then `monarch refresh shell`
