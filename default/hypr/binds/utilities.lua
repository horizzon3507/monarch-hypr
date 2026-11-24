-- Menus, captures, toggles and control panels.
local cmd = monarch.cmd

-- Menus (the launcher, emoji picker, clipboard manager and power menu are in shell.lua)
cmd("SUPER + CTRL + C", "monarch-menu trigger.capture", "Capture menu")
cmd("SUPER + CTRL + O", "monarch-menu trigger.toggle", "Toggle menu")
cmd("SUPER + CTRL + H", "monarch-menu trigger.hardware", "Hardware menu")
cmd("SUPER + ALT + space", "monarch-menu", "Monarch menu")
cmd("SUPER + K", "monarch-menu-keybindings", "Show key bindings")
cmd("XF86Calculator", "gnome-calculator", "Calculator")

-- Aesthetics
cmd("SUPER + CTRL + space", "monarch-menu style.background", "Background picker")
cmd("SUPER + SHIFT + CTRL + space", "monarch-menu style", "Style menu")
cmd("SUPER + BackSpace", "monarch-hypr-window-transparency-toggle", "Toggle window transparency")
cmd("SUPER + SHIFT + BackSpace", "monarch-hypr-window-gaps-toggle", "Toggle window gaps")

-- Toggles
cmd("SUPER + CTRL + comma", "monarch-toggle-notification-silencing", "Toggle Do Not Disturb")
cmd("SUPER + CTRL + I", "monarch-toggle-idle", "Toggle idle lock")
cmd("SUPER + CTRL + N", "monarch-toggle-nightlight", "Toggle nightlight")

-- Captures
cmd("Print", "monarch-capture-screenshot smart edit", "Screenshot (with editor)")
cmd("SUPER + SHIFT + S", "monarch-capture-screenshot smart copy", "Screenshot to clipboard")
cmd("ALT + Print", "monarch-menu trigger.capture.screenrecord", "Screen recording")
cmd("SUPER + ALT + minus", "monarch-capture-webcam-resize smaller", "Shrink webcam overlay")
cmd("SUPER + ALT + equal", "monarch-capture-webcam-resize larger", "Expand webcam overlay")
cmd("SUPER + Print", "monarch-capture-color", "Color picker")
cmd("SUPER + CTRL + Print", "monarch-capture-text-extraction", "OCR from screenshot")

-- Sharing, transcoding, reminders
cmd("SUPER + CTRL + S", "monarch-menu trigger.share", "Share")
cmd("SUPER + CTRL + semicolon", "monarch-transcode", "Transcode")
cmd("SUPER + CTRL + R", "monarch-menu trigger.reminder.set", "Set reminder")
cmd("SUPER + CTRL + ALT + R", "monarch-reminder show", "Show reminders")
cmd("SUPER + SHIFT + CTRL + R", "monarch-reminder clear", "Clear reminders")

-- Quick info
cmd("SUPER + CTRL + ALT + T", "notify-send -u low \"$(date +'%A %H:%M  -  %d %B W%V %Y')\"", "Show time")
cmd("SUPER + CTRL + ALT + B", "notify-send -u low \"$(monarch-battery-status)\"", "Show battery")
cmd("SUPER + CTRL + ALT + W", "notify-send -u low \"$(monarch-weather-status)\"", "Show weather")

-- Control panels
cmd("SUPER + CTRL + A", "monarch-launch-audio", "Audio controls")
cmd("SUPER + CTRL + B", "monarch-launch-bluetooth", "Bluetooth controls")
cmd("SUPER + CTRL + W", "monarch-launch-wifi", "Wifi controls")
cmd("SUPER + CTRL + P", "monarch-launch-powerprofile", "Power profile controls")
cmd("SUPER + CTRL + T", "monarch-launch-tui btop", "Activity (btop)")

-- Dictation (voxtype): press to start, press again to stop
cmd("SUPER + CTRL + X", "voxtype record toggle", "Toggle dictation")

-- Apple Display brightness
cmd("CTRL + F1", "monarch-brightness-display-apple -5000", "Apple Display brightness down")
cmd("CTRL + F2", "monarch-brightness-display-apple +5000", "Apple Display brightness up")
cmd("SHIFT + CTRL + F2", "monarch-brightness-display-apple +60000", "Apple Display full brightness")
