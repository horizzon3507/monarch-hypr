-- Look and feel. https://wiki.hypr.land/configuring/core/config-options/

-- Fallback colours; the active theme overrides them. The theme file returns
-- { activeBorder = "rgba(...)", inactiveBorder = "rgba(...)", accent, bg, fg }.
local theme = {
  activeBorder = "rgba(b471deee)",
  inactiveBorder = "rgba(3c2a6caa)",
}
local ok, current = pcall(dofile, os.getenv("HOME") .. "/.config/monarch/current/theme/hyprland.lua")
if ok and type(current) == "table" then
  for key, value in pairs(current) do
    theme[key] = value
  end
end
monarch.theme = theme

hl.config({
  general = {
    gaps_in = 4,
    gaps_out = 8,
    border_size = 2,
    col = { active_border = theme.activeBorder, inactive_border = theme.inactiveBorder },
    resize_on_border = true,
    allow_tearing = false,
    layout = "dwindle",
  },

  -- Light by default: no blur, no shadows. Rounded corners are cheap.
  decoration = {
    rounding = 6,
    shadow = { enabled = false },
    blur = { enabled = false },
  },

  group = {
    auto_group = true,
    col = {
      border_active = theme.activeBorder,
      border_inactive = theme.inactiveBorder,
      border_locked_active = theme.activeBorder,
      border_locked_inactive = theme.inactiveBorder,
    },
    groupbar = { height = 15, font_size = 12, font_weight_active = "bold", gradients = true },
  },

  dwindle = { preserve_split = true },
  master = { new_status = "master" },
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
})

-- Short, cheap animations
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.animation({ leaf = "global", enabled = true, speed = 6, bezier = "default" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 3, bezier = "easeOutQuint", style = "popin 90%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.5, bezier = "linear", style = "popin 90%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3, bezier = "easeOutQuint" })
hl.animation({ leaf = "fade", enabled = true, speed = 3, bezier = "easeOutQuint" })
hl.animation({ leaf = "layers", enabled = true, speed = 3, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "workspaces", enabled = false })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3, bezier = "easeOutQuint", style = "slidevert" })
