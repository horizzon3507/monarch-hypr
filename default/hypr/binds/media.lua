-- Hardware keys that do not go through the shell. Volume and display brightness
-- (with their on-screen display) are bound in shell.lua.
local cmd = monarch.cmd

cmd("XF86KbdBrightnessUp", "monarch-brightness-keyboard up", "Keyboard brightness up", { locked = true, repeating = true })
cmd("XF86KbdBrightnessDown", "monarch-brightness-keyboard down", "Keyboard brightness down", { locked = true, repeating = true })
cmd("XF86KbdLightOnOff", "monarch-brightness-keyboard cycle", "Keyboard backlight cycle", { locked = true })
cmd("XF86TouchpadToggle", "monarch-toggle-touchpad", "Toggle touchpad", { locked = true })
cmd("XF86TouchpadOn", "monarch-toggle-touchpad on", "Enable touchpad", { locked = true })
cmd("XF86TouchpadOff", "monarch-toggle-touchpad off", "Disable touchpad", { locked = true })

-- Requires playerctl
cmd("XF86AudioNext", "playerctl next", "Next track", { locked = true })
cmd("XF86AudioPause", "playerctl play-pause", "Pause", { locked = true })
cmd("XF86AudioPlay", "playerctl play-pause", "Play", { locked = true })
cmd("XF86AudioPrev", "playerctl previous", "Previous track", { locked = true })

-- Switch audio output with Super + Mute
cmd("SUPER + XF86AudioMute", "monarch-audio-output-switch", "Switch audio output", { locked = true })
