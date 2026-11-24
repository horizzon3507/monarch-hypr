-- Desktop shell: startup, shell keybinds and layer rules. Owned by the shell
-- layer (Quickshell, Walker, Mako, Hyprlock, Hypridle, Hyprpaper, SwayOSD).
-- Loaded by default/hypr/hyprland.lua after the core defaults; uses the helpers
-- from default/hypr/lib.lua (monarch.autostart, monarch.cmd).

monarch.autostart("monarch-shell-start")

-- Menus and launcher
monarch.cmd("SUPER + SPACE", "walker", "Launcher")
monarch.cmd("SUPER + ALT + SPACE", "monarch-menu", "Monarch menu")
monarch.cmd("SUPER + CTRL + SPACE", "monarch-menu style.background", "Background picker")
monarch.cmd("SUPER + SHIFT + CTRL + SPACE", "monarch-menu style", "Style menu")
monarch.cmd("SUPER + CTRL + E", "walker -m symbols", "Emoji picker")
monarch.cmd("SUPER + CTRL + C", "monarch-menu trigger.capture", "Capture menu")
monarch.cmd("SUPER + CTRL + O", "monarch-menu trigger.toggle", "Toggle menu")
monarch.cmd("SUPER + ALT + MINUS", "monarch-capture-webcam-resize smaller", "Shrink webcam overlay")
monarch.cmd("SUPER + ALT + EQUAL", "monarch-capture-webcam-resize larger", "Expand webcam overlay")
monarch.cmd("SUPER + CTRL + H", "monarch-menu trigger.hardware", "Hardware menu")
monarch.cmd("SUPER + CTRL + S", "monarch-menu trigger.share", "Share")
monarch.cmd("SUPER + CTRL + R", "monarch-menu trigger.reminder.set", "Set reminder")
monarch.cmd("SUPER + K", "monarch-menu-keybindings", "Show key bindings")
monarch.cmd("SUPER + SHIFT + V", "walker -m clipboard", "Clipboard manager")
monarch.cmd("SUPER + COMMA", "monarch-menu trigger.toggle", "Control center")
monarch.cmd("XF86PowerOff", "monarch-menu system", "Power menu")
monarch.cmd("SUPER + SHIFT + L", "monarch-menu system", "Power menu")

-- Session
monarch.cmd("SUPER + L", "monarch-system-lock", "Lock screen")

-- Toggles
monarch.cmd("SUPER + CTRL + COMMA", "monarch-toggle-notification-silencing", "Toggle Do Not Disturb")
monarch.cmd("SUPER + CTRL + I", "monarch-toggle-idle", "Toggle idle lock")
monarch.cmd("SUPER + CTRL + N", "monarch-toggle-nightlight", "Toggle nightlight")

-- Volume and brightness
monarch.cmd("XF86AudioRaiseVolume", "monarch-osd volume up", "Volume up", { locked = true, repeating = true })
monarch.cmd("XF86AudioLowerVolume", "monarch-osd volume down", "Volume down", { locked = true, repeating = true })
monarch.cmd("XF86AudioMute", "monarch-osd volume mute", "Mute", { locked = true })
monarch.cmd("XF86MonBrightnessUp", "monarch-osd brightness up", "Brightness up", { locked = true, repeating = true })
monarch.cmd("XF86MonBrightnessDown", "monarch-osd brightness down", "Brightness down", { locked = true, repeating = true })
monarch.cmd("SHIFT + XF86MonBrightnessUp", "monarch-osd brightness max", "Brightness max")
monarch.cmd("SHIFT + XF86MonBrightnessDown", "monarch-osd brightness min", "Brightness min")
monarch.cmd("ALT + XF86AudioRaiseVolume", "swayosd-client --output-volume +1", "Volume up precise", { locked = true, repeating = true })
monarch.cmd("ALT + XF86AudioLowerVolume", "swayosd-client --output-volume -1", "Volume down precise", { locked = true, repeating = true })
monarch.cmd("XF86AudioMicMute", "monarch-audio-input-mute", "Mic mute")

-- Layer rules
hl.layer_rule({ match = { namespace = "walker" }, no_anim = true })
hl.layer_rule({ match = { namespace = "selection" }, no_anim = true })
