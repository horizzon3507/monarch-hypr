-- Make every window opaque (flag: window-opaque)
hl.window_rule({ match = { class = ".*" }, opaque = true, opacity = "1 override 1 override 1 override" })
