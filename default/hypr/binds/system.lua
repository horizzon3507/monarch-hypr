-- System and applications
local bind, cmd = monarch.bind, monarch.cmd

bind("SUPER + Q", hl.dsp.window.close(), "Close active window")
bind("SUPER + SHIFT + Q", hl.dsp.window.close(), "Close active window")
cmd("CTRL + ALT + Delete", "monarch-hypr-window-close-all", "Close all windows")
cmd("SUPER + L", "monarch-system-lock", "Lock screen")
bind("SUPER + CTRL + ALT + Q", hl.dsp.exit(), "Exit Hyprland")

cmd("SUPER + Return", 'uwsm-app -- xdg-terminal-exec --dir="$(monarch-cmd-terminal-cwd)"', "Terminal")
cmd("SUPER + SHIFT + Return", 'uwsm-app -- xdg-terminal-exec --dir="$(monarch-cmd-terminal-cwd)" herdr', "Herdr terminal")
cmd("CTRL + ALT + F", "uwsm-app -- nautilus --new-window", "File manager")
cmd("CTRL + ALT + SHIFT + F", 'uwsm-app -- nautilus --new-window "$(monarch-cmd-terminal-cwd)"', "File manager (cwd)")
cmd("CTRL + ALT + S", "monarch-launch-floating-terminal-with-presentation sshm", "SSH manager")
cmd("CTRL + ALT + W", "monarch-launch-browser", "Browser")
cmd("ALT + SHIFT + W", "monarch-launch-browser --private", "Browser (private)")
cmd("SUPER + SHIFT + M", "monarch-launch-or-focus deezer-desktop", "Music")
cmd("SUPER + SHIFT + N", "monarch-launch-editor", "Editor")
cmd("SUPER + SHIFT + D", "monarch-launch-tui monarch-launch-docker-tui", "Docker (lazydocker)")
cmd("SUPER + SHIFT + O", 'monarch-launch-or-focus ^obsidian$ "uwsm-app -- obsidian"', "Obsidian")
cmd("SUPER + SHIFT + E", "monarch-launch-or-focus-webapp Outlook https://outlook.office.com", "Email (Outlook)")
cmd("SUPER + SHIFT + C", "monarch-launch-webapp Cyberchef https://gchq.github.io/CyberChef/", "Cyberchef")
cmd("SUPER + SHIFT + T", "monarch-launch-or-focus-webapp Teams https://teams.microsoft.com/", "Teams")
cmd("SUPER + SHIFT + Y", "monarch-launch-or-focus-webapp YouTube https://youtube.com/", "YouTube")

-- Extra bindings go in ~/.config/hypr/bindings.lua
