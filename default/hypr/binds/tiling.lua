local bind, cmd = monarch.bind, monarch.cmd
local dsp = hl.dsp

-- Control tiling
bind("SUPER + J", dsp.layout("togglesplit"), "Toggle window split")
bind("SUPER + P", dsp.window.pseudo(), "Pseudo window")
bind("SUPER + SHIFT + SPACE", dsp.window.float({ action = "toggle" }), "Toggle floating")
bind("SUPER + F", dsp.window.fullscreen({ mode = "fullscreen" }), "Fullscreen")
bind("SUPER + SHIFT + F", dsp.window.fullscreen({ mode = "maximized" }), "Maximize (keep bar and gaps)")
bind("SUPER + C", dsp.window.center(), "Center floating window")
bind("SUPER + H", dsp.layout("preselect r"), "Split next window to the right")
bind("SUPER + V", dsp.layout("preselect d"), "Split next window below")

-- Focus and swap with arrow keys
local directions = { left = "l", right = "r", up = "u", down = "d" }
local names = { left = "left", right = "right", up = "up", down = "down" }
for key, direction in pairs(directions) do
  bind("SUPER + " .. key, dsp.focus({ direction = direction }), "Move focus " .. names[key])
  bind("SUPER + SHIFT + " .. key, dsp.window.swap({ direction = direction }), "Swap window " .. names[key])
  bind("SUPER + CTRL + " .. key, dsp.workspace.move({ monitor = direction }), "Move workspace to the monitor " .. names[key])
end

-- Workspaces. Keycodes keep the number row working on every keyboard layout.
for index = 1, 10 do
  local code = "code:" .. (9 + index)
  bind("SUPER + " .. code, dsp.focus({ workspace = index }), "Switch to workspace " .. index)
  bind("SUPER + SHIFT + " .. code, dsp.window.move({ workspace = index }), "Move window to workspace " .. index)
end

-- Scratchpad
bind("SUPER + S", dsp.workspace.toggle_special("scratchpad"), "Toggle scratchpad")
bind("SUPER + ALT + S", dsp.window.move({ workspace = "special:scratchpad", follow = false }), "Move window to scratchpad")

-- Walk through workspaces
bind("SUPER + TAB", dsp.focus({ workspace = "e+1" }), "Next workspace")
bind("SUPER + SHIFT + TAB", dsp.focus({ workspace = "e-1" }), "Previous workspace")
bind("SUPER + CTRL + TAB", dsp.focus({ workspace = "previous" }), "Former workspace")
bind("SUPER + mouse_down", dsp.focus({ workspace = "e+1" }), "Scroll workspaces forward")
bind("SUPER + mouse_up", dsp.focus({ workspace = "e-1" }), "Scroll workspaces backward")

-- Cycle through windows and monitors
bind("ALT + TAB", function()
  hl.dispatch(dsp.window.cycle_next())
  hl.dispatch(dsp.window.alter_zorder({ mode = "top" }))
end, "Cycle to next window")
bind("ALT + SHIFT + TAB", function()
  hl.dispatch(dsp.window.cycle_next({ next = false }))
  hl.dispatch(dsp.window.alter_zorder({ mode = "top" }))
end, "Cycle to previous window")
bind("CTRL + ALT + TAB", dsp.focus({ monitor = "+1" }), "Focus next monitor")
bind("CTRL + ALT + SHIFT + TAB", dsp.focus({ monitor = "-1" }), "Focus previous monitor")

-- Resize with the minus and equals keys (any layout)
bind("SUPER + CTRL + code:20", dsp.window.resize({ x = -100, y = 0, relative = true }), "Shrink window width", { repeating = true })
bind("SUPER + CTRL + code:21", dsp.window.resize({ x = 100, y = 0, relative = true }), "Expand window width", { repeating = true })
bind("SUPER + CTRL + SHIFT + code:20", dsp.window.resize({ x = 0, y = -100, relative = true }), "Shrink window height", { repeating = true })
bind("SUPER + CTRL + SHIFT + code:21", dsp.window.resize({ x = 0, y = 100, relative = true }), "Expand window height", { repeating = true })

-- Move and resize windows with Super + mouse drag
bind("SUPER + mouse:272", dsp.window.drag(), "Move window", { mouse = true })
bind("SUPER + mouse:273", dsp.window.resize(), "Resize window", { mouse = true })

-- Display scaling and the laptop display
cmd("SUPER + CTRL + D", "monarch-hypr-monitor-scaling-cycle", "Cycle display scaling")
cmd("SUPER + CTRL + SHIFT + D", "monarch-hypr-monitor-scaling-cycle --reverse", "Cycle display scaling backwards")
cmd("SUPER + CTRL + Delete", "monarch-hypr-monitor-internal toggle", "Toggle laptop display")
cmd("SUPER + CTRL + ALT + Delete", "monarch-hypr-monitor-internal-mirror toggle", "Toggle laptop display mirroring")
-- Closing the lid always locks (as the Niri session did), then drops the laptop panel when an
-- external monitor is connected. MONARCH_LOCK_ONLY skips the display power-off in the lock command.
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("MONARCH_LOCK_ONLY=true monarch-system-lock; monarch-hw-external-monitors && monarch-hypr-monitor-internal off"), { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("monarch-hypr-monitor-internal on"), { locked = true })
