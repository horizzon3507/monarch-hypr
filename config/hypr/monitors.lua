-- See https://wiki.hypr.land/configuring/core/monitors/
-- List current monitors and modes: hyprctl monitors

-- Auto-detect everything at the preferred mode with automatic scale.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-- Pin a monitor
-- hl.monitor({ output = "DP-1", mode = "3840x2160@60", position = "0x0", scale = 1.5 })

-- Portrait secondary monitor (transform: 1 = 90 degrees, 3 = 270 degrees)
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })

-- Disable an output
-- hl.monitor({ output = "DP-3", disabled = true })
