-- https://wiki.hypr.land/configuring/core/config-options/
hl.config({
  input = {
    kb_layout = "us",
    kb_options = "compose:caps_toggle",
    numlock_by_default = true,

    -- Focus changes on click or keyboard only, as in the previous Monarch desktop
    follow_mouse = 1,
    sensitivity = 0,

    touchpad = {
      natural_scroll = true,
      scroll_factor = 0.4,
      clickfinger_behavior = true,
      tap_to_click = true,
    },
  },

  misc = {
    key_press_enables_dpms = true,
    mouse_move_enables_dpms = true,
  },
})
