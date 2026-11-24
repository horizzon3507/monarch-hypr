-- Grouping (tabbed stacks). Base combination: SUPER + ALT.
local bind = monarch.bind
local dsp = hl.dsp

bind("SUPER + ALT + Return", dsp.group.toggle(), "Start grouping")
bind("SUPER + ALT + U", dsp.window.move({ out_of_group = true }), "Unstack focused window")
bind("SUPER + ALT + L", dsp.group.lock({ action = "toggle" }), "Lock the active group")
bind("SUPER + ALT + SHIFT + L", dsp.group.lock({ all = true, action = "toggle" }), "Lock all groups")

for key, direction in pairs({ left = "l", right = "r", up = "u", down = "d" }) do
  bind("SUPER + ALT + " .. key, dsp.window.move({ into_or_create_group = direction }), "Stack into " .. key .. " group")
end

bind("SUPER + ALT + Page_Up", dsp.group.next(), "Next tab in group")
bind("SUPER + ALT + Page_Down", dsp.group.prev(), "Previous tab in group")
for index = 1, 10 do
  bind("SUPER + ALT + code:" .. (9 + index), dsp.group.active({ index = index }), "Tab " .. index .. " in group")
end

bind("SUPER + ALT + CTRL + left", dsp.group.move_window({ forward = false }), "Move tab backward")
bind("SUPER + ALT + CTRL + right", dsp.group.move_window({ forward = true }), "Move tab forward")
